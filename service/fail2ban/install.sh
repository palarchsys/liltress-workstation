#!/usr/bin/env bash
# =============================================================================
# File       : service/fail2ban/install.sh
# Updated at : 2026-11-07
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

apt_packages="fail2ban"
if check_workstation; then
    apt_packages="fail2ban python3-systemd"
fi
log_info         "${INSTALL_WATCHER}" "install.installation-of-fail2ban"
run_silent_apt   "${INSTALL_WATCHER}" "install -y ${apt_packages}" "install.fail2ban.error"
log_success      "${INSTALL_WATCHER}" "install.fail2ban-installed"

log_info         "${INSTALL_WATCHER}" "install.inclusion-of-the-units-possibly-added"
run_silent       "${INSTALL_WATCHER}" "install.fail2ban.error" systemctl daemon-reload
log_success      "${INSTALL_WATCHER}" "install.systemd-reloaded"
