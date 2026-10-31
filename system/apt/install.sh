#!/usr/bin/env bash
# =============================================================================
# File       : system/apt/install.sh
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
log_subtitle     "${INSTALL_WATCHER}" "install.update-system"
log_info         "${INSTALL_WATCHER}" "install.update-of-the-system"
run_silent_apt   "${INSTALL_WATCHER}" "update" "install.apt.error"
run_silent_apt   "${INSTALL_WATCHER}" "upgrade -y" "install.apt.error"
log_success      "${INSTALL_WATCHER}" "install.update-finished"
