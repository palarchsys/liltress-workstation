#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/brands/nordvpn.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Accept the OpenVPN profile this brand provides.
# -----------------------------------------------------------------------------


check_vpn_brand_nordvpn() {
    [[ "$1" == "openvpn" ]] || return 1
    check_vpn_brand_openvpn "$2" config.ovpn auth.txt
}
