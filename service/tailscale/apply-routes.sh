#!/usr/bin/env bash
# =============================================================================
# File       : service/tailscale/apply-routes.sh
# Updated at : 2026-11-23
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Keep ordinary traffic on the host default route.
# Note       : Only 100.64.0.0/10 consults Tailscale table 52.
# -----------------------------------------------------------------------------


# One priority can hold several copies. Stop when the priority is empty.
clear_tailscale_rule() {
    local prio="$1" guard=0
    while ((guard < 8)); do
        ip -4 rule del priority "${prio}" >/dev/null 2>&1 || return 0
        guard=$((guard + 1))
    done
}

# A miss in table 52 would fall through to main and into the VPN.
add_tailscale_prefix() {
    ip link show tailscale0 >/dev/null 2>&1 || return 0
    ip -4 route replace 100.64.0.0/10 dev tailscale0 table 52
}

# 5260 and 5265 sit after the fwmark rules and before the catch-all at 5270.
apply_tailscale_routes() {
    local net_prio=5260 rest_prio=5265
    clear_tailscale_rule "${net_prio}"
    clear_tailscale_rule "${rest_prio}"
    add_tailscale_prefix
    ip -4 rule add priority "${net_prio}" to 100.64.0.0/10 lookup 52
    ip -4 rule add priority "${rest_prio}" lookup main
}
set -euo pipefail

apply_tailscale_routes
