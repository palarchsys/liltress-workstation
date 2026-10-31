#!/usr/bin/env bash
# =============================================================================
# File       : system/multiarch/install.sh
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
log_subtitle     "${INSTALL_WATCHER}" "install.multiarch-i386"

if [[ "$(dpkg --print-architecture)" == "amd64" ]]; then
    log_info         "${INSTALL_WATCHER}" "install.check-of-the-architecture-i386"
    if dpkg --print-foreign-architectures | grep -qx 'i386'; then
        log_success      "${INSTALL_WATCHER}" "install.architecture-i386-already-enabled"
    else
        log_info         "${INSTALL_WATCHER}" "install.activation-of-the-architecture-i386"
        run_silent       "${INSTALL_WATCHER}" "install.multiarch.error" dpkg --add-architecture i386
        log_success      "${INSTALL_WATCHER}" "install.architecture-i386-enabled"
    fi
else
    log_info         "${INSTALL_WATCHER}" "install.architecture-i386-not-required-outside-amd64" "$(dpkg --print-architecture)"
fi
