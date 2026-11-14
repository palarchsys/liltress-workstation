#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/brands/cyberghost.sh
# Updated at : 2026-11-14
# Creator    : palarchsys
# =============================================================================

vpn_brand_cyberghost() {
    [[ "$1" == "openvpn" ]] || return 1
    vpn_brand_openvpn "$2" openvpn.ovpn ca.crt client.crt client.key auth.txt
}
