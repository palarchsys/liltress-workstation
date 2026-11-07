#!/usr/bin/env bash
# =============================================================================
# File       : service/rkhunter/install.sh
# Updated at : 2026-11-07
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info         "${INSTALL_WATCHER}" "install.installation-of-rkhunter"
run_silent_apt   "${INSTALL_WATCHER}" "install -y rkhunter" "install.rkhunter.error"
log_success      "${INSTALL_WATCHER}" "install.rkhunter-installed"

log_info         "${INSTALL_WATCHER}" "install.inclusion-of-the-units-possibly-added"
run_silent       "${INSTALL_WATCHER}" "install.rkhunter.error" systemctl daemon-reload
log_success      "${INSTALL_WATCHER}" "install.systemd-reloaded"
