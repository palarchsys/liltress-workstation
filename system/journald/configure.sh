#!/usr/bin/env bash
# =============================================================================
# File       : system/journald/configure.sh
# Updated at : 2026-11-05
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root
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
