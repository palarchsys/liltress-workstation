#!/usr/bin/env bash
# =============================================================================
# File       : service/usbguard/install.sh
# Updated at : 2026-11-07
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info         "${INSTALL_WATCHER}" "install.installation-of-usbguard"
if check_workstation; then
    run_silent_apt "${INSTALL_WATCHER}" "install -y usbguard usbguard-notifier" "install.usbguard.error"
else
    run_silent_apt "${INSTALL_WATCHER}" "install -y usbguard" "install.usbguard.error"
fi
run_optional     "${INSTALL_WATCHER}" "install.usbguard.error" systemctl disable --now usbguard
log_success      "${INSTALL_WATCHER}" "install.usbguard-installed-service-stopped-until-the-pol"
