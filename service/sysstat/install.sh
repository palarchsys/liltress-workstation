#!/usr/bin/env bash
# =============================================================================
# File       : service/sysstat/install.sh
# Updated at : 2026-11-05
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_subtitle     "${INSTALL_WATCHER}" "install.accounting-and-pam-lynis-acct-auth"
log_info         "${INSTALL_WATCHER}" "install.installation-of-the-accounting-and-of-pam"
run_silent_apt   "${INSTALL_WATCHER}" "install -y sysstat" "install.sysstat.error"
if [[ -f /etc/default/sysstat ]]; then
    sed -i 's/ENABLED="false"/ENABLED="true"/' /etc/default/sysstat
fi
run_optional     "${INSTALL_WATCHER}" "install.sysstat.error" systemctl enable --now sysstat
log_success      "${INSTALL_WATCHER}" "install.packages-acct-sysstat-and-libpam-pwquality-insta"
