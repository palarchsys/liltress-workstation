#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/brands/surfshark.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Accept the OpenVPN or WireGuard profile this brand provides.
# -----------------------------------------------------------------------------


check_vpn_brand_surfshark() {
    case "$1" in
        openvpn) check_vpn_brand_openvpn "$2" config.ovpn auth.txt ;;
        wireguard) check_vpn_brand_wireguard "$2" ;;
        *) return 1 ;;
    esac
}
