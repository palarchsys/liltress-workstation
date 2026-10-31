#!/usr/bin/env bash
# =============================================================================
# File       : service/fail2ban/install.sh
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

log_subtitle     "${INSTALL_WATCHER}" "install.installation-fail2ban"
log_info         "${INSTALL_WATCHER}" "install.installation-of-fail2ban"
run_silent_apt   "${INSTALL_WATCHER}" "install -y fail2ban python3-systemd" "install.fail2ban.error"
log_success      "${INSTALL_WATCHER}" "install.fail2ban-installed"
