#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/brands/windscribe.sh
# Updated at : 2026-11-14
# Creator    : palarchsys
# =============================================================================

vpn_brand_windscribe() {
    case "$1" in
        openvpn) vpn_brand_openvpn "$2" config.ovpn auth.txt ;;
        wireguard) vpn_brand_wireguard "$2" ;;
        *) return 1 ;;
    esac
}
