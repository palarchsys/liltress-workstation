#!/usr/bin/env bash
# =============================================================================
# File       : system/banners/configure.sh
# Updated at : 2026-11-05
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root
log_subtitle     "${INSTALL_WATCHER}" "configure.banners-lynis-bann-7126"
log_info         "${INSTALL_WATCHER}" "configure.install-of-the-banners"
copy_backup /etc/issue
printf '%s\n' "${BANNER_MESSAGE}" > /etc/issue
cp -f /etc/issue /etc/issue.net
log_success      "${INSTALL_WATCHER}" "configure.banners-installed-etc-issue-and-etc-issue-net"
