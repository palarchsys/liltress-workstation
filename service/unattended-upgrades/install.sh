#!/usr/bin/env bash
# =============================================================================
# File       : service/unattended-upgrades/install.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY
source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info         "${INSTALL_WATCHER}" "install.installation-of-unattended-upgrades"
run_silent_apt   "${INSTALL_WATCHER}" "install -y unattended-upgrades apt-listchanges" "install.unattended-upgrades.error"
log_success      "${INSTALL_WATCHER}" "install.unattended-upgrades-installed"
