#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/brands/perso.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Accept one WireGuard file from the server panel.
# Note       : OpenVPN is refused.
# -----------------------------------------------------------------------------


check_vpn_brand_perso() {
    [[ "$1" == "wireguard" ]] || return 1
    check_vpn_brand_wireguard "$2"
}
