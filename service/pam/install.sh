#!/usr/bin/env bash
# =============================================================================
# File       : service/pam/install.sh
# Updated at : 2026-11-07
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

if ! check_workstation; then
    log_info         "${INSTALL_WATCHER}" "install.installation-of-libpam-tmpdir"
    run_silent_apt   "${INSTALL_WATCHER}" "install -y libpam-tmpdir" "install.pam.error"
    log_success      "${INSTALL_WATCHER}" "install.libpam-tmpdir-installed"
fi

log_info         "${INSTALL_WATCHER}" "install.installation-of-libpam-pwquality"
run_silent_apt   "${INSTALL_WATCHER}" "install -y libpam-pwquality" "install.pam.error"
log_success      "${INSTALL_WATCHER}" "install.libpam-pwquality-installed"
