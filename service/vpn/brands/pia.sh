#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/brands/pia.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Accept the OpenVPN profile this brand provides.
# -----------------------------------------------------------------------------


check_vpn_brand_pia() {
    [[ "$1" == "openvpn" ]] || return 1
    check_vpn_brand_openvpn "$2" config.ovpn auth.txt
}
