#!/usr/bin/env bash
# =============================================================================
# File       : service/ufw/install.sh
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

log_subtitle     "${INSTALL_WATCHER}" "install.installation-ufw"
log_info         "${INSTALL_WATCHER}" "install.installation-of-ufw-2"
run_silent_apt   "${INSTALL_WATCHER}" "install -y ufw" "install.ufw.error"
run_silent       "${INSTALL_WATCHER}" "install.ufw.error" systemctl enable ufw
log_success      "${INSTALL_WATCHER}" "install.ufw-installed"
