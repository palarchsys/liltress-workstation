#!/usr/bin/env bash
# =============================================================================
# File       : system/base/install.sh
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
    log_info         "${INSTALL_WATCHER}" "install.update-of-the-index-apt"
    run_silent_apt   "${INSTALL_WATCHER}" "update" "install.base.error"
fi
log_info         "${INSTALL_WATCHER}" "install.installation-of-the-tools-of-base"
if check_workstation; then
    apt_packages="apt-listchanges needrestart apt-show-versions curl openssl rsync ca-certificates jq gnupg gettext-base lsb-release"
else
    apt_packages="apt-listchanges needrestart apt-show-versions curl openssl rsync inotify-tools cpulimit ca-certificates jq gnupg gettext-base cryptsetup"
fi
run_silent_apt   "${INSTALL_WATCHER}" "install -y ${apt_packages}" "install.base.error"
log_success      "${INSTALL_WATCHER}" "install.tools-of-base-installed"
