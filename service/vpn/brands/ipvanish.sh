#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/brands/ipvanish.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Accept the OpenVPN profile this brand provides.
# -----------------------------------------------------------------------------


vpn_brand_ipvanish() {
    [[ "$1" == "openvpn" ]] || return 1
    vpn_brand_openvpn "$2" config.ovpn auth.txt
}
