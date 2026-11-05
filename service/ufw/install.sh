#!/usr/bin/env bash
# =============================================================================
# File       : service/ufw/install.sh
# Updated at : 2026-11-05
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info         "${INSTALL_WATCHER}" "install.installation-of-ufw-2"
run_silent_apt   "${INSTALL_WATCHER}" "install -y ufw" "install.ufw.error"
run_silent       "${INSTALL_WATCHER}" "install.ufw.error" systemctl enable ufw
log_success      "${INSTALL_WATCHER}" "install.ufw-installed"
