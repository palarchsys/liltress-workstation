#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/cli.sh
# Updated at : 2026-11-14
# Creator    : palarchsys
# =============================================================================

set -euo pipefail

VPN_SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "${VPN_SRC}/../.." && pwd)"
export PRODUCT_ROOT="${ROOT}"
export INSTALL_DIRECTORY="${ROOT}"
INSTALL_WATCHER="${INSTALL_WATCHER:-BASH}"
export INSTALL_WATCHER

# shellcheck disable=SC1091
source "${ROOT}/core/boot/lib.sh"
# shellcheck disable=SC1091
source "${ROOT}/config/global.conf"
# shellcheck disable=SC1091
source "${VPN_SRC}/lib.sh"
# shellcheck disable=SC1091
source "${VPN_SRC}/state.sh"
# shellcheck disable=SC1091
source "${VPN_SRC}/killswitch.sh"
# shellcheck disable=SC1091
source "${VPN_SRC}/routes.sh"
# shellcheck disable=SC1091
source "${VPN_SRC}/import.sh"
# shellcheck disable=SC1091
source "${VPN_SRC}/nm.sh"
# shellcheck disable=SC1091
source "${VPN_SRC}/up.sh"
# shellcheck disable=SC1091
source "${VPN_SRC}/down.sh"
# shellcheck disable=SC1091
source "${VPN_SRC}/switch.sh"
# shellcheck disable=SC1091
source "${VPN_SRC}/failover.sh"

require_root
load_vpn_settings

show_vpn_usage() {
    printf '%s\n' "$(get_text vpn.usage)" >&2
    exit 2
}

remove_vpn_profile() {
    local name="${1:-}" active total
    [[ -n "${name}" ]] || show_vpn_usage
    if ! check_vpn_name "${name}"; then
        note_vpn_log rm "${name}" fail "bad-name"
        log_error "${INSTALL_WATCHER}" "vpn.import.bad-name" "${name}"
    fi
    if [[ ! -d "$(get_vpn_profile_dir "${name}")" || ! -f "$(get_vpn_profile_dir "${name}")/meta" ]]; then
        note_vpn_log rm "${name}" fail "missing"
        log_error "${INSTALL_WATCHER}" "vpn.rm.missing" "${name}"
    fi
    active="$(get_vpn_active 2>/dev/null || true)"
    total="$(count_vpn_profiles)"
    if [[ "${active}" == "${name}" && "${total}" != "1" ]]; then
        note_vpn_log rm "${name}" fail "active"
        log_error "${INSTALL_WATCHER}" "vpn.rm.active" "${name}"
    fi
    forget_vpn_profile "${name}" "rm"
}

show_vpn_status() {
    local armed=0 name proto iface handshake count code=0 mode
    load_vpn_settings
    mode="${VPN_MODE:-off}"
    printf '%s\n' "$(get_text vpn.status.mode "${mode}")"
    if check_vpn_killswitch; then
        armed=1
        printf '%s\n' "$(get_text vpn.status.armed)"
    else
        printf '%s\n' "$(get_text vpn.status.disarmed)"
    fi
    name="$(get_vpn_active 2>/dev/null || true)"
    if [[ -z "${name}" && "${armed}" -eq 1 ]]; then
        name="${VPN_BOOT_PROFILE:-}"
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
    local home dir name proto found=0 kind valid validated observed tested state brand
    home="$(get_vpn_home)"
    refresh_vpn_state
    shopt -s nullglob
    for kind in wireguard openvpn profiles; do
        for dir in "${home}/${kind}"/*/; do
            [[ -d "${dir}" ]] || continue
            name="$(basename -- "${dir}")"
            check_vpn_name "${name}" || continue
            proto="$(get_vpn_meta "${name}" proto 2>/dev/null || echo "${kind}")"
            valid="false"
            validated=""
            observed=""
            tested=""
            if state="$(show_vpn_profile_state "${name}" 2>/dev/null)"; then
                valid="$(printf '%s\n' "${state}" | sed -n '1p')"
                validated="$(printf '%s\n' "${state}" | sed -n '2p')"
                observed="$(printf '%s\n' "${state}" | sed -n '3p')"
                tested="$(printf '%s\n' "${state}" | sed -n '4p')"
            fi
            brand="$(get_vpn_meta "${name}" brand 2>/dev/null || true)"
            printf '%s  %s\n' "$(get_text vpn.list.line "${name}" "${proto}" "${valid}" "${validated}" "${observed}" "${tested}" "${brand}")" "${dir%/}"
            found=1
        done
    done
    shopt -u nullglob
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
            apply_vpn_nft "${VPN_BOOT_PROFILE}" 0
        else
            apply_vpn_nft "" 0
        fi
    fi
    log_success "${INSTALL_WATCHER}" "vpn.bypass.reloaded"
}

arm_vpn_boot() {
    load_vpn_settings
    if ! check_vpn_mode; then
        clear_vpn_network
        log_info "${INSTALL_WATCHER}" "vpn.direct.ok"
        exit 0
    fi
    apply_vpn_nft "" 0 || true
    apply_vpn_bypass_routes || true
    exit 0
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
        [[ $# -eq 4 ]] || show_vpn_usage
        case "$1" in
            wireguard|openvpn) install_vpn_bundle "$1" "$2" "$3" "$4" ;;
            *) show_vpn_usage ;;
        esac
        ;;
    test)
        [[ $# -eq 1 ]] || show_vpn_usage
        run_vpn_test "$1"
        ;;
    switch)
        [[ $# -eq 1 ]] || show_vpn_usage
        run_vpn_switch "$1"
        ;;
    mode)
        [[ $# -eq 1 ]] || show_vpn_usage
        case "$1" in
            on) run_vpn_mode_on ;;
            off) run_vpn_mode_off ;;
            *) show_vpn_usage ;;
        esac
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
        load_vpn_settings
        if ! check_vpn_mode; then
            clear_vpn_network
            exit 0
        fi
        run_vpn_failover
        exit 0
        ;;
    *)
        show_vpn_usage
        ;;
esac
