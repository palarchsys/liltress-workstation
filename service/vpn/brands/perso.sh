#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/brands/perso.sh
# Updated at : 2026-11-17
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Accept one WireGuard file from the server panel.
# Note       : OpenVPN is refused.
# -----------------------------------------------------------------------------


vpn_brand_perso() {
    [[ "$1" == "wireguard" ]] || return 1
    vpn_brand_wireguard "$2"
}
