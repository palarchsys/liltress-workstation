#!/usr/bin/env bash
# =============================================================================
# File       : system/banners/configure.sh
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
log_subtitle     "${INSTALL_WATCHER}" "configure.banners-lynis-bann-7126"
log_info         "${INSTALL_WATCHER}" "configure.install-of-the-banners"
copy_backup /etc/issue
printf '%s\n' "${G_BANNER_MESSAGE}" > /etc/issue
cp -f /etc/issue /etc/issue.net
log_success      "${INSTALL_WATCHER}" "configure.banners-installed-etc-issue-and-etc-issue-net"
