#!/usr/bin/env bash
# =============================================================================
# File       : system/purge/coredump.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info "${INSTALL_WATCHER}" "log.masking-of-systemd-coredump"
run_optional "${INSTALL_WATCHER}" "install.purge.error" systemctl mask systemd-coredump.socket
log_success "${INSTALL_WATCHER}" "log.systemd-coredump-masked"
