#!/usr/bin/env bash
# =============================================================================
# File       : system/purge/coredump.sh
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

log_info "${INSTALL_WATCHER}" "log.masking-of-systemd-coredump"
run_optional "${INSTALL_WATCHER}" "install.purge.error" systemctl mask systemd-coredump.socket
log_success "${INSTALL_WATCHER}" "log.systemd-coredump-masked"
