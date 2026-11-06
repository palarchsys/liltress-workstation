#!/usr/bin/env bash
# =============================================================================
# File       : service/aide/install.sh
# Updated at : 2026-11-06
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY
source "${INSTALL_DIRECTORY}/core/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info         "${INSTALL_WATCHER}" "install.installation-of-help-2"
run_silent_apt   "${INSTALL_WATCHER}" "install -y aide aide-common" "install.aide.error"
if systemctl cat dailyaidecheck.timer >/dev/null 2>&1; then
    run_optional "${INSTALL_WATCHER}" "install.aide.error" systemctl disable --now dailyaidecheck.timer
    run_optional "${INSTALL_WATCHER}" "install.aide.error" systemctl mask dailyaidecheck.timer
fi
log_success      "${INSTALL_WATCHER}" "install.help-installed"
