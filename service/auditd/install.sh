#!/usr/bin/env bash
# =============================================================================
# File       : service/auditd/install.sh
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

log_subtitle     "${INSTALL_WATCHER}" "install.installation-auditd"
log_info         "${INSTALL_WATCHER}" "install.installation-of-auditd-2"
run_silent_apt   "${INSTALL_WATCHER}" "install -y auditd audispd-plugins" "install.auditd.error"
log_success      "${INSTALL_WATCHER}" "install.auditd-installed-2"
