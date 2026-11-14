#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/brands/pia.sh
# Updated at : 2026-11-14
# Creator    : palarchsys
# =============================================================================

vpn_brand_pia() {
    [[ "$1" == "openvpn" ]] || return 1
    vpn_brand_openvpn "$2" config.ovpn auth.txt
}
