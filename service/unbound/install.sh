#!/usr/bin/env bash
# =============================================================================
# File       : service/unbound/install.sh
# Updated at : 2026-11-07
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info         "${INSTALL_WATCHER}" "install.installation-of-unbound"
run_silent_apt   "${INSTALL_WATCHER}" "install -y unbound dns-root-data" "install.unbound.error"
log_success      "${INSTALL_WATCHER}" "install.unbound-installed"
