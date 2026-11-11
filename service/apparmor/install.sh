#!/usr/bin/env bash
# =============================================================================
# File       : service/apparmor/install.sh
# Updated at : 2026-11-07
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

# The workstation does not install apparmor-profiles-extra.
apt_packages="apparmor apparmor-utils"
if ! check_workstation; then
    apt_packages="apparmor apparmor-utils apparmor-profiles apparmor-profiles-extra apparmor-easyprof"
fi
log_info         "${INSTALL_WATCHER}" "install.installation-of-apparmor"
run_silent_apt   "${INSTALL_WATCHER}" "install -y ${apt_packages}" "install.apparmor.error"
log_success      "${INSTALL_WATCHER}" "install.apparmor-installed"

log_info         "${INSTALL_WATCHER}" "install.inclusion-of-the-units-possibly-added"
run_silent       "${INSTALL_WATCHER}" "install.apparmor.error" systemctl daemon-reload
log_success      "${INSTALL_WATCHER}" "install.systemd-reloaded"
