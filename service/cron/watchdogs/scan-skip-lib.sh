#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/scan-skip-lib.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================


locate_python_dir() {
    local dir hops=0 candidate
    for candidate in \
        "${CONFIG_BASE_DIRECTORY:-}/python" \
        "${BASE:-}/python" \
        "${INSTALL_DIRECTORY:-}/python" \
        "${INSTALL_DIRECTORY:-}/../share/python"
    do
        if [[ -n "${candidate}" && -d "${candidate}" ]]; then
            (cd -- "${candidate}" && pwd -P)
            return 0
        fi
    done
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        if [[ -d "${dir}/share/python" ]]; then
            printf '%s\n' "${dir}/share/python"
            return 0
        fi
        if [[ -d "${dir}/python" ]]; then
            (cd -- "${dir}/python" && pwd -P)
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

BASE="${BASE:-/opt/liltress-workstation}"

render_scan_skip_path() {
    python3 "$(locate_python_dir)/scan-skip-path.py" norm "$1"
}

check_scan_skip_forbidden() {
    printf '%s\n' / /home /opt /tmp /etc /usr /var /boot /root
    if [[ -f /etc/clamav/clamd.conf ]]; then
        awk '/^OnAccessIncludePath[[:space:]]/{print $2}' /etc/clamav/clamd.conf
    fi
}

get_scan_skip_home() {
    local line trimmed home homes=""
    if [[ "${SCAN_SKIP_HOME:-}" =~ ^/home/[^/]+$ ]]; then
        printf '%s\n' "${SCAN_SKIP_HOME}"
        return 0
    fi
    [[ -f "${SCAN_SKIP_FILE}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^[[:space:]]*#[[:space:]]*home=(/home/[^/]+)[[:space:]]*$ ]]; then
            printf '%s\n' "${BASH_REMATCH[1]}"
            return 0
        fi
    done < "${SCAN_SKIP_FILE}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        [[ -z "${trimmed}" || "${trimmed}" == \#* ]] && continue
        if [[ "${trimmed}" =~ ^(/home/[^/]+)/ ]]; then
            home="${BASH_REMATCH[1]}"
            case "${homes}" in
                *"|${home}|"*) ;;
                *) homes="${homes}|${home}|" ;;
            esac
        fi
    done < "${SCAN_SKIP_FILE}"
    homes="${homes#|}"
    homes="${homes%|}"
    [[ -n "${homes}" && "${homes}" != *"|"* ]] || return 1
    printf '%s\n' "${homes}"
}

check_scan_skip_path() {
    local norm bad home=""
    norm="$(render_scan_skip_path "$1")" || return 1
    home="$(get_scan_skip_home || true)"
    if [[ "${norm}" == /var/jeux || "${norm}" == /var/jeux/* ]]; then
        :
    elif [[ -n "${home}" && "${norm}" == "${home}/"* ]]; then
        :
    else
        return 1
    fi
    while IFS= read -r bad; do
        [[ -z "${bad}" ]] && continue
        [[ "${norm}" == "${bad}" ]] && return 1
        [[ "${bad}" == "${norm}/"* ]] && return 1
    done < <(check_scan_skip_forbidden)
    [[ "${norm}" =~ ^/home/[^/]+$ ]] && return 1
    printf '%s\n' "${norm}"
}

collect_scan_skip_path() {
    SCAN_SKIP_VALID=()
    SCAN_SKIP_BAD=()
    [[ -f "${SCAN_SKIP_FILE}" ]] || return 0
    local line norm seen="|"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "${line}" || "${line}" == \#* ]] && continue
        if norm="$(check_scan_skip_path "${line}")"; then
            [[ "${seen}" == *"|${norm}|"* ]] && continue
            seen="${seen}${norm}|"
            SCAN_SKIP_VALID+=("${norm}")
        else
            SCAN_SKIP_BAD+=("${line}")
        fi
    done < "${SCAN_SKIP_FILE}"
}

locate_scan_skip_file() {
    local here candidate found
    here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    if ! declare -F locate_config_file >/dev/null 2>&1; then
        for candidate in \
            "${INSTALL_DIRECTORY:-}/core/host/fs.sh" \
            "${here}/../../../core/host/fs.sh" \
            "${here}/../../../../share/core/host/fs.sh" \
            "${here}/../../src/core/host/fs.sh" \
            "${BASE}/src/core/host/fs.sh"
        do
            [[ -n "${candidate}" && -f "${candidate}" ]] || continue
            # shellcheck disable=SC1090
            source "${candidate}"
            break
        done
    fi
    if declare -F locate_config_file >/dev/null 2>&1; then
        if found="$(locate_config_file clamav/scan-skip.paths)"; then
            printf '%s\n' "${found}"
            return 0
        fi
    fi
    for candidate in \
        "${INSTALL_DIRECTORY:-}/config/clamav/scan-skip.paths" \
        "${here}/../../../config/clamav/scan-skip.paths" \
        "${here}/../../src/config/clamav/scan-skip.paths" \
        "${BASE}/src/config/clamav/scan-skip.paths"
    do
        [[ -n "${candidate}" && -f "${candidate}" ]] || continue
        printf '%s\n' "${candidate}"
        return 0
    done
    if [[ -n "${INSTALL_DIRECTORY:-}" ]]; then
        printf '%s\n' "${INSTALL_DIRECTORY}/config/clamav/scan-skip.paths"
        return 0
    fi
    printf '%s\n' "${BASE}/src/config/clamav/scan-skip.paths"
}

ensure_scan_skip_file() {
    local home="$1"
    local template legacy dest base
    template="$(locate_scan_skip_file)"
    legacy="${BASE}/cron/scan-skip.paths"
    dest="${template}"
    if [[ "${dest}" != "${BASE}/"* ]]; then
        if [[ -z "${CONFIG_BASE_DIRECTORY:-}" || "${dest}" != "${CONFIG_BASE_DIRECTORY}/"* ]]; then
            dest="${BASE}/src/config/clamav/scan-skip.paths"
        fi
    fi
    SCAN_SKIP_FILE="${dest}"
    if [[ -f "${dest}" ]] && ! grep -q '__HOME__' "${dest}"; then
        return 0
    fi
    if [[ -f "${legacy}" ]]; then
        install -d -m 755 "$(dirname "${dest}")"
        cp -a "${legacy}" "${dest}"
        chmod 644 "${dest}"
        chown root:root "${dest}"
        return 0
    fi
    [[ "${home}" =~ ^/home/[^/]+$ && -d "${home}" ]] || return 1
    [[ -f "${template}" ]] || return 1
    base="${BASE}"
    install -d -m 755 "$(dirname "${dest}")"
    sed -e "s|__HOME__|${home}|g" -e "s|__HFU_BASE__|${base}|g" "${template}" > "${dest}.new"
    cat "${dest}.new" > "${dest}"
    rm -f "${dest}.new"
    chmod 644 "${dest}"
    chown root:root "${dest}"
}

SCAN_SKIP_FILE="$(locate_scan_skip_file)"
