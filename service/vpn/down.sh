#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/down.sh
# Updated at : 2026-11-04
# Creator    : palarchsys
# =============================================================================

clear_vpn_network() {
    local name
    load_vpn_settings
    name="$(get_vpn_active 2>/dev/null || true)"
    if [[ -n "${name}" ]]; then
        remove_vpn_iface "${name}"
    fi
    ip link del "${W_VPN_IFACE_WG}" >/dev/null 2>&1 || true
    ip link del "${W_VPN_IFACE_OVPN}" >/dev/null 2>&1 || true
    clear_vpn_routes || true
    clear_vpn_killswitch || true
    clear_vpn_active
}

run_vpn_down() {
    clear_vpn_network
    log_success "${INSTALL_WATCHER:-BASH}" "vpn.down.ok"
}
