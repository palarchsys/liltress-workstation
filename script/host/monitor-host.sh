#!/usr/bin/env bash
# =============================================================================
# File       : script/host/monitor-host.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================
# -----------------------------------------------------------------------------
# Purpose    : Print the host name, the OS id and whether the install directory exists.
# Note       : The script does not change the machine. The directory comes from global.conf.
# -----------------------------------------------------------------------------

set -u

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
product_root="$(cd -- "${script_dir}/../.." && pwd)"
install_dir=""
if [[ -f "${product_root}/config/global.conf" ]]; then
    # shellcheck disable=SC1091
    source "${product_root}/config/global.conf"
    install_dir="${CONFIG_BASE_DIRECTORY:-}"
fi

read_host_name() {
    local name=""
    name="$(hostname 2>/dev/null || true)"
    name="${name//$'\n'/}"
    if [[ -z "${name}" ]]; then
        name="unknown"
    fi
    printf '%s' "${name}"
}

read_os_field() {
    local key="$1"
    local value=""
    set +u
    # shellcheck disable=SC1091
    source /etc/os-release
    set -u
    case "${key}" in
        id) value="${ID:-unknown}" ;;
        version) value="${VERSION_ID:-unknown}" ;;
        *) value="unknown" ;;
    esac
    printf '%s' "${value}"
}

read_install_state() {
    if [[ -n "${install_dir}" && -d "${install_dir}" ]]; then
        printf 'present'
        return 0
    fi
    printf 'absent'
}

install_state="$(read_install_state)"
printf 'hostname=%s\n' "$(read_host_name)"
printf 'os=%s\n' "$(read_os_field id)"
printf 'version=%s\n' "$(read_os_field version)"
printf 'install=%s\n' "${install_state}"
if [[ "${install_state}" == "present" ]]; then
    printf 'success\n'
else
    printf 'warning\n'
fi
