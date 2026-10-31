#!/usr/bin/env bash
# =============================================================================
# File       : service/unbound/install.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY
G_INSTALL_DIRECTORY="${INSTALL_DIRECTORY}"
export G_INSTALL_DIRECTORY
source "${G_INSTALL_DIRECTORY}/core/lib.sh"
source "${G_INSTALL_DIRECTORY}/config/global.conf"
require_root

log_subtitle     "${INSTALL_WATCHER}" "install.installation-unbound"
log_info         "${INSTALL_WATCHER}" "install.installation-of-unbound"
run_silent_apt   "${INSTALL_WATCHER}" "install -y unbound dns-root-data" "install.unbound.error"
log_success      "${INSTALL_WATCHER}" "install.unbound-installed"
