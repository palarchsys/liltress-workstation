#!/usr/bin/env bash
# =============================================================================
# File       : service/ufw/install.sh
# Updated at : 2026-11-07
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info         "${INSTALL_WATCHER}" "install.installation-of-ufw"
run_silent_apt   "${INSTALL_WATCHER}" "install -y ufw" "install.ufw.error"
run_silent       "${INSTALL_WATCHER}" "install.ufw.error" systemctl enable ufw
log_success      "${INSTALL_WATCHER}" "install.ufw-installed"

log_info         "${INSTALL_WATCHER}" "install.inclusion-of-the-units-possibly-added"
run_silent       "${INSTALL_WATCHER}" "install.ufw.error" systemctl daemon-reload
log_success      "${INSTALL_WATCHER}" "install.systemd-reloaded"
