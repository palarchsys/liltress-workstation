#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/brands/purevpn.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Accept the OpenVPN or WireGuard profile this brand provides.
# -----------------------------------------------------------------------------


vpn_brand_purevpn() {
    case "$1" in
        openvpn) vpn_brand_openvpn "$2" config.ovpn auth.txt ;;
        wireguard) vpn_brand_wireguard "$2" ;;
        *) return 1 ;;
    esac
}
