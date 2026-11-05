#!/usr/bin/env bash
# =============================================================================
# File       : system/base/install.sh
# Updated at : 2026-11-05
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root
log_info         "${INSTALL_WATCHER}" "install.installation-of-the-tools-of-base"
run_silent_apt   "${INSTALL_WATCHER}" "install -y apt-listchanges needrestart apt-show-versions curl openssl rsync ca-certificates jq gnupg gettext-base lsb-release" "install.base.error"
log_success      "${INSTALL_WATCHER}" "install.tools-of-base-installed"
