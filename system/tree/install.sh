#!/usr/bin/env bash
# =============================================================================
# File       : system/tree/install.sh
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
log_subtitle     "${INSTALL_WATCHER}" "install.tree-project"
log_info         "${INSTALL_WATCHER}" "log.creation-of" "${G_CONFIG_BASE_DIRECTORY}"
ensure_directory "${G_CONFIG_BASE_DIRECTORY}" 755
ensure_directory "${G_SECRET_DIRECTORY}" 700
log_success      "${INSTALL_WATCHER}" "install.directories-project-ready"
