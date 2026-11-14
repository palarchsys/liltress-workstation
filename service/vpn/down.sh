#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/down.sh
# Updated at : 2026-11-14
# Creator    : palarchsys
# =============================================================================

clear_vpn_network() {
    local name
    load_vpn_settings
    if declare -F vpn_nm_held >/dev/null 2>&1 && ! vpn_nm_held; then
        vpn_nm_hold_on
        if ! check_vpn_mode; then
            vpn_nm_autoconnect_all false || true
        fi
        stop_vpn_nm_all || true
        vpn_nm_hold_off
    fi
    name="$(get_vpn_active 2>/dev/null || true)"
    if [[ -n "${name}" ]] && declare -F remove_vpn_iface >/dev/null 2>&1; then
        remove_vpn_iface "${name}"
    fi
    ip link del "${VPN_IFACE_WG}" >/dev/null 2>&1 || true
    ip link del "${VPN_IFACE_OVPN}" >/dev/null 2>&1 || true
    clear_vpn_routes || true
    if declare -F release_vpn_direct >/dev/null 2>&1; then
        release_vpn_direct || true
    fi
    clear_vpn_killswitch || true
    if declare -F clear_vpn_active >/dev/null 2>&1; then
        clear_vpn_active
    else
        rm -f "$(get_vpn_home)/active"
    fi
}

