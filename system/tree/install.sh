#!/usr/bin/env bash
# =============================================================================
# File       : system/tree/install.sh
# Updated at : 2026-11-07
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info         "${INSTALL_WATCHER}" "install.creation-tree-secured-of-the-project"
ensure_directory "${CONFIG_BASE_DIRECTORY}" 755
ensure_directory "${SECRET_DIRECTORY}" 700
if ! check_workstation; then
    ensure_directory "${DOCKER_BASE_DIRECTORY}" 755
fi
log_success      "${INSTALL_WATCHER}" "install.directories-project-ready"

if ! check_workstation; then
    set_main_hostname
    log_info         "${INSTALL_WATCHER}" "install.configuration-of-the-hostname"
    hostnamectl set-hostname "${MAIN_HOSTNAME}"
    log_success      "${INSTALL_WATCHER}" "install.hostname-configured"
fi
