#!/usr/bin/env bash
# =============================================================================
# File       : service/acct/install.sh
# Updated at : 2026-11-05
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info         "${INSTALL_WATCHER}" "install.installation-of-acct"
run_silent_apt   "${INSTALL_WATCHER}" "install -y acct" "install.acct.error"
run_optional     "${INSTALL_WATCHER}" "install.acct.error" systemctl enable --now acct
log_success      "${INSTALL_WATCHER}" "install.acct-installed"
