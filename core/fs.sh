#!/usr/bin/env bash
# =============================================================================
# File       : core/fs.sh
# Updated at : 2026-11-07
# Creator    : palarchsys
# =============================================================================

locate_config_file() {
    local rel="$1"
    local root candidate shared_parent probe
    local seen="|"
    local roots=()

    if [[ -n "${INSTALL_DIRECTORY:-}" ]]; then
        roots+=("${INSTALL_DIRECTORY}")
    fi
    if [[ -n "${PRODUCT_ROOT:-}" ]]; then
        roots+=("${PRODUCT_ROOT}")
    fi
    if [[ -n "${CONFIG_BASE_DIRECTORY:-}" ]]; then
        roots+=("${CONFIG_BASE_DIRECTORY}/src" "${CONFIG_BASE_DIRECTORY}")
    fi
    if [[ -n "${BASE:-}" ]]; then
        roots+=("${BASE}/src" "${BASE}")
    fi
    for probe in "${INSTALL_DIRECTORY:-}" "${PRODUCT_ROOT:-}"; do
        [[ -n "${probe}" && -d "${probe}" ]] || continue
        if shared_parent="$(cd -- "${probe}/.." && pwd)"; then
            if [[ -d "${shared_parent}/share/core" && -d "${shared_parent}/config" ]]; then
                roots+=("${shared_parent}")
                break
            fi
        fi
    done

    for root in "${roots[@]}"; do
        [[ -n "${root}" ]] || continue
        [[ "${seen}" == *"|${root}|"* ]] && continue
        seen="${seen}${root}|"
        candidate="${root}/config/${rel}"
        if [[ -f "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    return 1
}

add_line() {
    local file="$1"
    local line="$2"
    local comment="${3:-}"
    if ! grep -qF "$line" "$file" 2>/dev/null; then
        [[ -n "$comment" ]] && echo "$comment" >> "$file"
        echo "$line" >> "$file"
    fi
}

copy_backup() {
    local file="$1"
    local backup="${file}.bak"
    [[ -f "$file" ]] || return 0
    [[ -f "$backup" ]] && return 0
    log_info "${INSTALL_WATCHER:-BASH}" "install.fs.info" "${file}"
    cp -a "$file" "$backup" && log_success "${INSTALL_WATCHER:-BASH}" "install.fs.success" "${backup}"
}

ensure_directory() {
    local mode="700"
    local user="root"
    local group="root"
    local dirs=()

    while [ $# -gt 0 ]; do
        case "$1" in
            [0-9]*)
                mode="$1"
                shift
                break
                ;;
            *)
                dirs+=("$1")
                shift
                ;;
        esac
    done

    if [ $# -ge 1 ]; then
        user="$1"
    fi
    if [ $# -ge 2 ]; then
        group="$2"
    fi

    local dir effective_user effective_group
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        chmod "$mode" "$dir"

        effective_user="$user"
        effective_group="$group"

        if ! id -u "$effective_user" >/dev/null 2>&1; then
            effective_user="root"
        fi
        if ! getent group "$effective_group" >/dev/null 2>&1; then
            effective_group="root"
        fi

        chown "${effective_user}:${effective_group}" "$dir" 2>/dev/null || true
    done
}

check_user() {
    local user="$1"
    id "$user" >/dev/null 2>&1
}

set_usb_rule() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "${daemon_conf}"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "${daemon_conf}"
    else
        printf '%s=%s\n' "${key}" "${value}" >> "${daemon_conf}"
    fi
}

load_usb_rule() {
    local line key value
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" || "${line}" == \#* ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        set_usb_rule "${key}" "${value}"
    done < "$(locate_config_file usbguard/daemon.conf)"
}

copy_runtime_dir() {
    local src="$1" dest="$2" src_real="" dest_real=""
    [[ -d "${src}" ]] || return 0
    src_real="$(readlink -f "${src}")"
    if [[ -d "${dest}" ]]; then
        dest_real="$(readlink -f "${dest}" 2>/dev/null || true)"
        [[ "${src_real}" == "${dest_real}" ]] && return 0
    fi
    install -d -m 755 "${dest}"
    cp -a "${src_real}/." "${dest}/"
}

encode_url() {
    local s="$1" byte c out=""
    while IFS= read -r byte; do
        [[ -n "${byte}" ]] || continue
        if [[ "${byte}" -eq 45 || "${byte}" -eq 46 || "${byte}" -eq 95 || "${byte}" -eq 126 \
            || ( "${byte}" -ge 48 && "${byte}" -le 57 ) \
            || ( "${byte}" -ge 65 && "${byte}" -le 90 ) \
            || ( "${byte}" -ge 97 && "${byte}" -le 122 ) ]]; then
            printf -v c '%b' "$(printf '\\%03o' "${byte}")"
            out+="${c}"
        else
            printf -v c "$(get_text install.02x)" "${byte}"
            out+="%${c}"
        fi
    done < <(printf '%s' "${s}" | od -An -tu1 -v | tr -s '[:space:]' '\n')
    printf '%s' "${out}"
}

persist_mode() {
    local mode="$1" path="$2" group="${3:-root}"
    [[ -e "${path}" ]] || return 0
    if dpkg-statoverride --list "${path}" >/dev/null 2>&1; then
        dpkg-statoverride --remove "${path}" >/dev/null
    fi
    dpkg-statoverride --update --add root "${group}" "${mode}" "${path}" >/dev/null
}
