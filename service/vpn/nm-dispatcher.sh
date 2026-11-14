#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/nm-dispatcher.sh
# Updated at : 2026-11-14
# Creator    : palarchsys
# =============================================================================

ROOT="@ROOT@"
export PRODUCT_ROOT="${ROOT}"
export INSTALL_DIRECTORY="${ROOT}"
export INSTALL_WATCHER="${INSTALL_WATCHER:-BASH}"

# shellcheck disable=SC1091
source "${ROOT}/core/boot/lib.sh"
# shellcheck disable=SC1091
source "${ROOT}/config/global.conf"
# shellcheck disable=SC1091
source "${ROOT}/service/vpn/lib.sh"
# shellcheck disable=SC1091
source "${ROOT}/service/vpn/state.sh"
# shellcheck disable=SC1091
source "${ROOT}/service/vpn/killswitch.sh"
# shellcheck disable=SC1091
source "${ROOT}/service/vpn/routes.sh"
# shellcheck disable=SC1091
source "${ROOT}/service/vpn/nm.sh"
# shellcheck disable=SC1091
source "${ROOT}/service/vpn/down.sh"
handle_vpn_nm_event "${1:-}" "${2:-}"
exit 0
