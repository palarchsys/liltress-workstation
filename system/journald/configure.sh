#!/usr/bin/env bash
# =============================================================================
# File       : system/journald/configure.sh
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
log_subtitle     "${INSTALL_WATCHER}" "configure.persistent-journald-lynis-log"
log_info         "${INSTALL_WATCHER}" "configure.configuration-of-journald"
ensure_directory /etc/systemd/journald.conf.d 755
tee /etc/systemd/journald.conf.d/persistent.conf > /dev/null << EOF
[Journal]
Storage=persistent
SystemMaxUse=512M
RuntimeMaxUse=64M
ForwardToSyslog=no
EOF
rm -f /etc/systemd/journald.conf.d/volatile.conf
run_silent       "${INSTALL_WATCHER}" "configure.journald.error" systemctl restart systemd-journald
log_success      "${INSTALL_WATCHER}" "configure.journald-made-persistent"
