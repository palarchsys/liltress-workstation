#!/usr/bin/env bash
# =============================================================================
# File       : system/tree/install.sh
# Updated at : 2026-11-05
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root
log_info         "${INSTALL_WATCHER}" "log.creation-of" "${CONFIG_BASE_DIRECTORY}"
ensure_directory "${CONFIG_BASE_DIRECTORY}" 755
ensure_directory "${SECRET_DIRECTORY}" 700
log_success      "${INSTALL_WATCHER}" "install.directories-project-ready"
