#!/usr/bin/env bash
# =============================================================================
# File       : system/purge/relock.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Mask the coredump socket again after an upgrade.
# -----------------------------------------------------------------------------


INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info "${INSTALL_WATCHER}" "log.the-last-upgrade-can-re-enable-systemd-coredump"
# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/system/purge/coredump.sh"
