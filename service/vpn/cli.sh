#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/cli.sh
# Updated at : 2026-11-04
# Creator    : palarchsys
# =============================================================================

set -euo pipefail

VPN_SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "${VPN_SRC}/../.." && pwd)"
export G_PRODUCT_ROOT="${ROOT}"
export G_INSTALL_DIRECTORY="${ROOT}"
INSTALL_WATCHER="${INSTALL_WATCHER:-BASH}"
export INSTALL_WATCHER

# shellcheck disable=SC1091
source "${ROOT}/core/lib.sh"
# shellcheck disable=SC1091
source "${ROOT}/config/global.conf"
# shellcheck disable=SC1091
source "${VPN_SRC}/lib.sh"
# shellcheck disable=SC1091
source "${VPN_SRC}/killswitch.sh"
# shellcheck disable=SC1091
source "${VPN_SRC}/routes.sh"
# shellcheck disable=SC1091
source "${VPN_SRC}/import.sh"
# shellcheck disable=SC1091
source "${VPN_SRC}/up.sh"
# shellcheck disable=SC1091
source "${VPN_SRC}/down.sh"
# shellcheck disable=SC1091
source "${VPN_SRC}/switch.sh"

require_root
load_vpn_settings

show_vpn_usage() {
    printf '%s\n' "$(get_text vpn.usage)" >&2
    exit 2
}

write_vpn_boot() {
    local enabled="$1" profile="$2" file
    file="$(get_vpn_home)/boot.conf"
    mkdir -p "$(get_vpn_home)"
    umask 077
    cat > "${file}" << EOF
W_VPN_ON_BOOT=${enabled}
W_VPN_BOOT_PROFILE=${profile}
EOF
    chmod 600 "${file}"
    load_vpn_settings
    apply_vpn_systemd
}

run_vpn_boot() {
    local name="${1:-}"
    if [[ "${name}" == "off" ]]; then
        write_vpn_boot 0 ""
        log_success "${INSTALL_WATCHER}" "vpn.boot.off"
        return 0
    fi
    [[ -n "${name}" ]] || show_vpn_usage
    check_vpn_name "${name}" || log_error "${INSTALL_WATCHER}" "vpn.import.bad-name" "${name}"
    [[ -f "$(get_vpn_profile_dir "${name}")/runtime" ]] || log_error "${INSTALL_WATCHER}" "vpn.boot.bad" "${name}"
    if check_vpn_encrypted "${name}"; then
        log_error "${INSTALL_WATCHER}" "vpn.boot.encrypted" "${name}"
    fi
    write_vpn_boot 1 "${name}"
    log_success "${INSTALL_WATCHER}" "vpn.boot.ok" "${name}"
}

remove_vpn_profile() {
    local name="${1:-}" active boot
    [[ -n "${name}" ]] || show_vpn_usage
    check_vpn_name "${name}" || log_error "${INSTALL_WATCHER}" "vpn.import.bad-name" "${name}"
    [[ -d "$(get_vpn_profile_dir "${name}")" && -f "$(get_vpn_profile_dir "${name}")/meta" ]] || log_error "${INSTALL_WATCHER}" "vpn.rm.missing" "${name}"
    active="$(get_vpn_active 2>/dev/null || true)"
    [[ "${active}" == "${name}" ]] && log_error "${INSTALL_WATCHER}" "vpn.rm.active" "${name}"
    boot="${W_VPN_BOOT_PROFILE:-}"
    if [[ "${W_VPN_ON_BOOT}" == "1" && "${boot}" == "${name}" ]]; then
        log_error "${INSTALL_WATCHER}" "vpn.rm.boot" "${name}"
    fi
    rm -rf "$(get_vpn_profile_dir "${name}")"
    log_success "${INSTALL_WATCHER}" "vpn.rm.ok" "${name}"
}

show_vpn_status() {
    local armed=0 name proto iface handshake count code=0
    if check_vpn_killswitch; then
        armed=1
        printf '%s\n' "$(get_text vpn.status.armed)"
    else
        printf '%s\n' "$(get_text vpn.status.disarmed)"
    fi
    name="$(get_vpn_active 2>/dev/null || true)"
    if [[ -z "${name}" && "${armed}" -eq 1 ]]; then
        name="${W_VPN_BOOT_PROFILE:-}"
    fi
    proto=""
    iface=""
    handshake="-"
    if [[ -n "${name}" && -f "$(get_vpn_profile_dir "${name}")/meta" ]]; then
        proto="$(get_vpn_meta "${name}" proto 2>/dev/null || true)"
        iface="$(get_vpn_meta "${name}" iface 2>/dev/null || true)"
        if [[ -f "$(get_vpn_profile_dir "${name}")/handshake" ]]; then
            handshake="$(tr -d '[:space:]' < "$(get_vpn_profile_dir "${name}")/handshake")"
        fi
        printf '%s\n' "$(get_text vpn.status.line "${name}" "${proto}" "${iface}" "${handshake}")"
    else
        printf '%s\n' "$(get_text vpn.status.none)"
    fi
    if [[ "${armed}" -eq 1 ]]; then
        count="$(get_vpn_bypass_count)"
        printf '%s\n' "$(get_text vpn.status.bypass "${count}")"
    fi
    if [[ -n "${name}" ]] && check_vpn_tunnel "${name}"; then
        code=0
    elif [[ "${armed}" -eq 1 ]]; then
        code=1
    fi
    exit "${code}"
}

list_vpn_profiles() {
    local home dir name proto boot_word found=0 kind
    home="$(get_vpn_home)"
    shopt -s nullglob
    for kind in wireguard openvpn profiles; do
        for dir in "${home}/${kind}"/*/; do
            [[ -d "${dir}" ]] || continue
            name="$(basename -- "${dir}")"
            check_vpn_name "${name}" || continue
            proto="$(get_vpn_meta "${name}" proto 2>/dev/null || echo "${kind}")"
            if check_vpn_encrypted "${name}"; then
                boot_word="$(get_text vpn.list.boot-no)"
            else
                boot_word="$(get_text vpn.list.boot-yes)"
            fi
            printf '%s  %s\n' "$(get_text vpn.list.line "${name}" "${proto}" "${boot_word}")" "${dir%/}"
            found=1
        done
    done
    if (( found == 0 )); then
        printf '%s\n' "$(get_text vpn.list.empty)"
    fi
}

show_vpn_bypass() {
    local file line
    file="$(get_vpn_home)/bypass.cidrs"
    printf '%s\n' "$(get_text vpn.bypass.head "${file}")"
    if [[ -f "${file}" ]]; then
        cat "${file}"
    fi
    while IFS= read -r line; do
        printf '%s\n' "$(get_text vpn.bypass.implicit "${line}")"
    done < <(list_vpn_implicit)
    printf '%s\n' "$(get_text vpn.bypass.implicit "DHCP 68:67 546:547")"
}

run_vpn_bypass_reload() {
    local home="${1:-}"
    home="$(get_vpn_home)"
    if [[ ! -f "${home}/bypass.cidrs" ]]; then
        log_error "${INSTALL_WATCHER}" "vpn.bypass.bad" "${home}/bypass.cidrs"
    fi
    if ! write_vpn_bypass "${home}/bypass.cidrs" "${home}/bypass.applied"; then
        log_error "${INSTALL_WATCHER}" "vpn.bypass.kept"
    fi
    if check_vpn_killswitch; then
        apply_vpn_bypass_routes
        if [[ -n "$(get_vpn_active 2>/dev/null || true)" ]]; then
            apply_vpn_nft "$(get_vpn_active)" 1
        elif check_vpn_boot_on; then
            apply_vpn_nft "${W_VPN_BOOT_PROFILE}" 0
        else
            apply_vpn_nft "" 0
        fi
    fi
    log_success "${INSTALL_WATCHER}" "vpn.bypass.reloaded"
}

check_vpn_boot() {
    load_vpn_settings
    check_vpn_boot_on || return 1
    [[ -n "${W_VPN_BOOT_PROFILE}" && -f "$(get_vpn_profile_dir "${W_VPN_BOOT_PROFILE}")/runtime" ]]
}

arm_vpn_boot() {
    if ! check_vpn_boot; then
        clear_vpn_network
        log_info "${INSTALL_WATCHER}" "vpn.direct.ok"
        exit 0
    fi
    if check_vpn_encrypted "${W_VPN_BOOT_PROFILE}"; then
        log_error "${INSTALL_WATCHER}" "vpn.boot.encrypted" "${W_VPN_BOOT_PROFILE}"
    fi
    arm_vpn_closed "${W_VPN_BOOT_PROFILE}" || log_error "${INSTALL_WATCHER}" "vpn.profile.invalid" "${W_VPN_BOOT_PROFILE}"
}

cmd="${1:-}"
shift || true

case "${cmd}" in
    status)
        [[ $# -eq 0 ]] || show_vpn_usage
        show_vpn_status
        ;;
    list)
        [[ $# -eq 0 ]] || show_vpn_usage
        list_vpn_profiles
        ;;
    import)
        [[ $# -eq 3 ]] || show_vpn_usage
        case "$1" in
            wireguard) install_vpn_wireguard "$2" "$3" ;;
            openvpn) install_vpn_openvpn "$2" "$3" ;;
            *) show_vpn_usage ;;
        esac
        ;;
    up)
        [[ $# -eq 1 ]] || show_vpn_usage
        run_vpn_up "$1"
        ;;
    down)
        [[ $# -eq 0 ]] || show_vpn_usage
        run_vpn_down
        ;;
    switch)
        [[ $# -eq 1 ]] || show_vpn_usage
        run_vpn_switch "$1"
        ;;
    boot)
        [[ $# -eq 1 ]] || show_vpn_usage
        run_vpn_boot "$1"
        ;;
    rm)
        [[ $# -eq 1 ]] || show_vpn_usage
        remove_vpn_profile "$1"
        ;;
    bypass)
        if [[ $# -eq 0 ]]; then
            show_vpn_bypass
        elif [[ $# -eq 1 && "$1" == "reload" ]]; then
            run_vpn_bypass_reload
        else
            show_vpn_usage
        fi
        ;;
    refresh-endpoint)
        [[ $# -eq 1 ]] || show_vpn_usage
        refresh_vpn_endpoint "$1"
        ;;
    boot-killswitch)
        arm_vpn_boot
        ;;
    boot-up)
        if ! check_vpn_boot; then
            clear_vpn_network
            exit 0
        fi
        run_vpn_up "${W_VPN_BOOT_PROFILE}"
        ;;
    *)
        show_vpn_usage
        ;;
esac
