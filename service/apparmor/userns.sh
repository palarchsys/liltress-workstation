#!/usr/bin/env bash
# =============================================================================
# File       : service/apparmor/userns.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info "${INSTALL_WATCHER}" "log.detection-of-the-profiles-userns"
bash "${INSTALL_DIRECTORY}/service/apparmor/detect-and-apply.sh" "${INSTALL_DIRECTORY}"
run_optional "${INSTALL_WATCHER}" "install.apparmor.error" systemctl reload apparmor
log_success "${INSTALL_WATCHER}" "log.profiles-userns-loaded"
