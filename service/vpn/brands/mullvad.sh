#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/brands/mullvad.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Accept the WireGuard profile this brand provides.
# -----------------------------------------------------------------------------


vpn_brand_mullvad() {
    [[ "$1" == "wireguard" ]] || return 1
    vpn_brand_wireguard "$2"
}
