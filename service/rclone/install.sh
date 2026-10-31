#!/usr/bin/env bash
# =============================================================================
# File       : service/rclone/install.sh
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

log_subtitle     "${INSTALL_WATCHER}" "install.installation-of-rclone"
if [[ "${G_RCLONE_ALERTS:-0}" != "1" ]]; then
    log_info         "${INSTALL_WATCHER}" "install.send-google-drive-cut-rclone-is-not-installed"
    exit 0
fi
log_info         "${INSTALL_WATCHER}" "install.installation-of-rclone"
run_silent_apt   "${INSTALL_WATCHER}" "install --no-install-recommends -y rclone" "install.rclone.error"
token="${G_CONFIG_BASE_DIRECTORY}/cron/rclone.conf"
mode="$(stat -c %a "${token}" 2>/dev/null || true)"
if [[ ! -f "${token}" || "${mode}" != "600" ]]; then
    log_error        "${INSTALL_WATCHER}" "install.token-google-drive-absent-or-mode-different-of-6" "${token}"
fi
log_success      "${INSTALL_WATCHER}" "install.rclone-installed"
