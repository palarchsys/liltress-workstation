#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/brands/cyberghost.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Accept the OpenVPN profile and certificate files this brand provides.
# -----------------------------------------------------------------------------


check_vpn_brand_cyberghost() {
    [[ "$1" == "openvpn" ]] || return 1
    check_vpn_brand_openvpn "$2" openvpn.ovpn ca.crt client.crt client.key auth.txt
}
