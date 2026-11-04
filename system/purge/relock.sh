#!/usr/bin/env bash
# =============================================================================
# File       : system/purge/relock.sh
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

log_subtitle "${INSTALL_WATCHER}" "log.reapplication-of-the-deactivations"
log_info "${INSTALL_WATCHER}" "log.the-last-upgrade-can-re-enable-systemd-coredump"
bash "${G_INSTALL_DIRECTORY}/system/purge/coredump.sh" "${INSTALL_WATCHER}" "${G_INSTALL_DIRECTORY}"
