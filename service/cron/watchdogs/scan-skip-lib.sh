#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/scan-skip-lib.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Resolve the paths kept out of the on-access scanner.
# Note       : A marked home line wins over the paths in the file.
# Note       : One home directory is accepted.
# -----------------------------------------------------------------------------


source_python_boot() {
    local dir hops
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    hops=0
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        if [[ -f "${dir}/core/boot/python.sh" ]]; then
            # shellcheck disable=SC1090
            source "${dir}/core/boot/python.sh"
            return 0
        fi
        if [[ -f "${dir}/share/core/boot/python.sh" ]]; then
            # shellcheck disable=SC1090
            source "${dir}/share/core/boot/python.sh"
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

source_python_boot

render_scan_skip_path() {
    python3 "$(locate_python_dir)/scan-skip-path.py" norm "$1"
}

check_scan_skip_forbidden() {
    printf '%s\n' / /home /opt /tmp /etc /usr /var /boot /root
    if [[ -f /etc/clamav/clamd.conf ]]; then
        awk '/^OnAccessIncludePath[[:space:]]/{print $2}' /etc/clamav/clamd.conf
    fi
}

# A comment can name one home directory.
read_scan_skip_marked_home() {
    local line
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^[[:space:]]*#[[:space:]]*home=(/home/[^/]+)[[:space:]]*$ ]]; then
            printf '%s\n' "${BASH_REMATCH[1]}"
            return 0
        fi
    done <"${SCAN_SKIP_FILE}"
    return 1
}

# A blank line or a comment is not a path.
skip_scan_skip_note() {
    local trimmed="$1"
    [[ -z "${trimmed}" || "${trimmed}" == \#* ]]
}

# Paths that share one home directory name that directory.
read_scan_skip_path_home() {
    local line trimmed home homes=""
    while IFS= read -r line || [[ -n "${line}" ]]; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        skip_scan_skip_note "${trimmed}" && continue
        if [[ "${trimmed}" =~ ^(/home/[^/]+)/ ]]; then
            home="${BASH_REMATCH[1]}"
            case "${homes}" in
                *"|${home}|"*) ;;
                *) homes="${homes}|${home}|" ;;
            esac
        fi
    done <"${SCAN_SKIP_FILE}"
    homes="${homes#|}"
    homes="${homes%|}"
    [[ -n "${homes}" && "${homes}" != *"|"* ]] || return 1
    printf '%s\n' "${homes}"
}

get_scan_skip_home() {
    if [[ "${SCAN_SKIP_HOME:-}" =~ ^/home/[^/]+$ ]]; then
        printf '%s\n' "${SCAN_SKIP_HOME}"
        return 0
    fi
    [[ -f "${SCAN_SKIP_FILE}" ]] || return 1
    read_scan_skip_marked_home && return 0
    read_scan_skip_path_home
}

# One home directory is accepted.
check_scan_skip_root() {
    local norm="$1"
    local home="$2"
    if [[ -n "${home}" && "${norm}" == "${home}/"* ]]; then
        return 0
    fi
    return 1
}

# A forbidden path and its parent are refused.
check_scan_skip_blocked() {
    local norm="$1"
    local bad
    while IFS= read -r bad; do
        [[ -z "${bad}" ]] && continue
        [[ "${norm}" == "${bad}" ]] && return 1
        [[ "${bad}" == "${norm}/"* ]] && return 1
    done < <(check_scan_skip_forbidden)
    [[ "${norm}" =~ ^/home/[^/]+$ ]] && return 1
    return 0
}

check_scan_skip_path() {
    local norm home=""
    norm="$(render_scan_skip_path "$1")" || return 1
    home="$(get_scan_skip_home || true)"
    check_scan_skip_root "${norm}" "${home}" || return 1
    check_scan_skip_blocked "${norm}" || return 1
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
    done <"${SCAN_SKIP_FILE}"
}

# The shared engine file is loaded when it is present.
source_scan_skip_fs() {
    local here="$1"
    local candidate
    for candidate in \
        "${INSTALL_DIRECTORY:-}/core/host/fs.sh" \
        "${here}/../../../core/host/fs.sh" \
        "${here}/../../../../share/core/host/fs.sh" \
        "${here}/../../core/host/fs.sh" \
        "${BASE}/core/host/fs.sh"; do
        [[ -n "${candidate}" && -f "${candidate}" ]] || continue
        # shellcheck disable=SC1090
        source "${candidate}"
        break
    done
}

# The first existing list is printed.
find_scan_skip_candidate() {
    local here="$1"
    local candidate
    for candidate in \
        "${INSTALL_DIRECTORY:-}/config/service/clamav/scan-skip.paths" \
        "${here}/../../../config/service/clamav/scan-skip.paths" \
        "${here}/../../config/service/clamav/scan-skip.paths" \
        "${BASE}/config/service/clamav/scan-skip.paths"; do
        [[ -n "${candidate}" && -f "${candidate}" ]] || continue
        printf '%s\n' "${candidate}"
        return 0
    done
    return 1
}

locate_scan_skip_file() {
    local here found
    here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    if ! declare -F locate_config_file >/dev/null 2>&1; then
        source_scan_skip_fs "${here}"
    fi
    if declare -F locate_config_file >/dev/null 2>&1; then
        if found="$(locate_config_file service/clamav/scan-skip.paths)"; then
            printf '%s\n' "${found}"
            return 0
        fi
    fi
    if find_scan_skip_candidate "${here}"; then
        return 0
    fi
    if [[ -n "${INSTALL_DIRECTORY:-}" ]]; then
        printf '%s\n' "${INSTALL_DIRECTORY}/config/service/clamav/scan-skip.paths"
        return 0
    fi
    printf '%s\n' "${BASE}/config/service/clamav/scan-skip.paths"
}

# A list outside the two known roots is stored under the product.
choose_scan_skip_dest() {
    local dest="$1"
    if [[ "${dest}" != "${BASE}/"* ]]; then
        if [[ -z "${CONFIG_BASE_DIRECTORY:-}" || "${dest}" != "${CONFIG_BASE_DIRECTORY}/"* ]]; then
            printf '%s\n' "${BASE}/config/service/clamav/scan-skip.paths"
            return 0
        fi
    fi
    printf '%s\n' "${dest}"
}

# An older list is copied into place.
copy_scan_skip_legacy() {
    local legacy="$1"
    local dest="$2"
    install -d -m 755 "$(dirname "${dest}")"
    cp -a "${legacy}" "${dest}"
    chmod 644 "${dest}"
    chown root:root "${dest}"
}

# The markers in the template are replaced.
render_scan_skip_template() {
    local template="$1"
    local dest="$2"
    local home="$3"
    local base
    base="${BASE}"
    install -d -m 755 "$(dirname "${dest}")"
    sed -e "s|__HOME__|${home}|g" -e "s|__HFU_BASE__|${base}|g" "${template}" >"${dest}.new"
    cat "${dest}.new" >"${dest}"
    rm -f "${dest}.new"
    chmod 644 "${dest}"
    chown root:root "${dest}"
}

ensure_scan_skip_file() {
    local home="$1"
    local template legacy dest
    template="$(locate_scan_skip_file)"
    legacy="${BASE}/cron/scan-skip.paths"
    dest="$(choose_scan_skip_dest "${template}")"
    SCAN_SKIP_FILE="${dest}"
    if [[ -f "${dest}" ]] && ! grep -q '__HOME__' "${dest}"; then
        return 0
    fi
    if [[ -f "${legacy}" ]]; then
        copy_scan_skip_legacy "${legacy}" "${dest}"
        return 0
    fi
    [[ "${home}" =~ ^/home/[^/]+$ && -d "${home}" ]] || return 1
    [[ -f "${template}" ]] || return 1
    render_scan_skip_template "${template}" "${dest}" "${home}"
}

BASE="${BASE:-/opt/liltress-workstation}"

SCAN_SKIP_FILE="$(locate_scan_skip_file)"
