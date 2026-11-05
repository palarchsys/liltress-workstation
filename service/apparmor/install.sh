#!/usr/bin/env bash
# =============================================================================
# File       : service/apparmor/install.sh
# Updated at : 2026-11-05
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY
source "${INSTALL_DIRECTORY}/core/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_subtitle     "${INSTALL_WATCHER}" "install.installation-apparmor-2"

log_info         "${INSTALL_WATCHER}" "install.installation-of-apparmor-2"
run_silent_apt   "${INSTALL_WATCHER}" "install -y apparmor apparmor-utils" "install.apparmor.error"
log_success      "${INSTALL_WATCHER}" "install.apparmor-installed-profiles-of-the-distribution"
