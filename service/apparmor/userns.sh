#!/usr/bin/env bash
# =============================================================================
# File       : service/apparmor/userns.sh
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

log_subtitle "${INSTALL_WATCHER}" "log.profiles-apparmor-userns"
log_info "${INSTALL_WATCHER}" "log.detection-of-the-profiles-userns"
bash "${G_INSTALL_DIRECTORY}/service/apparmor/detect-and-apply.sh" "${G_INSTALL_DIRECTORY}"
run_optional "${INSTALL_WATCHER}" "install.apparmor.error" systemctl reload apparmor
log_success "${INSTALL_WATCHER}" "log.profiles-userns-loaded"
