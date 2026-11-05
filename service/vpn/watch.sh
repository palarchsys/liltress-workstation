#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/watch.sh
# Updated at : 2026-11-05
# Creator    : palarchsys
# =============================================================================

set -euo pipefail

VPN_SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "${VPN_SRC}/../.." && pwd)"
export PRODUCT_ROOT="${ROOT}"
export INSTALL_DIRECTORY="${ROOT}"
INSTALL_WATCHER="${INSTALL_WATCHER:-BASH}"
export INSTALL_WATCHER

# shellcheck disable=SC1091
source "${ROOT}/core/lib.sh"
# shellcheck disable=SC1091
source "${ROOT}/config/global.conf"
# shellcheck disable=SC1091
source "${VPN_SRC}/lib.sh"
# shellcheck disable=SC1091
source "${VPN_SRC}/state.sh"
# shellcheck disable=SC1091
source "${VPN_SRC}/killswitch.sh"
# shellcheck disable=SC1091
source "${VPN_SRC}/routes.sh"
# shellcheck disable=SC1091
source "${VPN_SRC}/import.sh"
# shellcheck disable=SC1091
source "${VPN_SRC}/up.sh"
# shellcheck disable=SC1091
source "${VPN_SRC}/down.sh"
# shellcheck disable=SC1091
source "${VPN_SRC}/failover.sh"

require_root
run_vpn_watch
