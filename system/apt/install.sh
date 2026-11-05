#!/usr/bin/env bash
# =============================================================================
# File       : system/apt/install.sh
# Updated at : 2026-11-05
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root
log_subtitle     "${INSTALL_WATCHER}" "install.update-system"
log_info         "${INSTALL_WATCHER}" "install.update-of-the-system"
run_silent_apt   "${INSTALL_WATCHER}" "update" "install.apt.error"
run_silent_apt   "${INSTALL_WATCHER}" "upgrade -y" "install.apt.error"
log_success      "${INSTALL_WATCHER}" "install.update-finished"
