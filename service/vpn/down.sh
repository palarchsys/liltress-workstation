#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/down.sh
# Updated at : 2026-11-21
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Drop the tunnel, the routes, and the firewall hold.
# Note       : The hold covers the profile stop and is released afterwards.
# -----------------------------------------------------------------------------


# Hold NetworkManager across the profile stop.
clear_vpn_nm() {
    if declare -F vpn_nm_held >/dev/null 2>&1 && ! vpn_nm_held; then
        vpn_nm_hold_on
        stop_vpn_nm_all || true
        vpn_nm_hold_off
    fi
}

# Remove the live interface, then the two tunnel devices.
clear_vpn_links() {
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
}

# Release the firewall hold and forget the active name.
finish_vpn_down() {
    clear_vpn_killswitch || true
    if declare -F clear_vpn_active >/dev/null 2>&1; then
        clear_vpn_active
    else
        rm -f "$(get_vpn_home)/active"
    fi
    if declare -F vpn_nm_apply_autoconnect >/dev/null 2>&1; then
        vpn_nm_apply_autoconnect || true
    fi
    if declare -F restart_vpn_services >/dev/null 2>&1; then
        restart_vpn_services || true
    fi
}

clear_vpn_network() {
    local name
    load_vpn_settings
    clear_vpn_nm
    clear_vpn_links
    finish_vpn_down
}
