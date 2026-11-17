#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/brands/expressvpn.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Accept the OpenVPN profile this brand provides.
# -----------------------------------------------------------------------------


vpn_brand_expressvpn() {
    [[ "$1" == "openvpn" ]] || return 1
    vpn_brand_openvpn "$2" config.ovpn auth.txt
}
