#!/usr/bin/env bash
# =============================================================================
# File       : service/rclone/install.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

if [[ "${RCLONE_ALERTS:-0}" != "1" ]]; then
    log_info         "${INSTALL_WATCHER}" "install.send-google-drive-cut-rclone-is-not-installed"
    exit 0
fi
log_info         "${INSTALL_WATCHER}" "install.installation-of-rclone"
run_silent_apt   "${INSTALL_WATCHER}" "install --no-install-recommends -y rclone" "install.rclone.error"
token="${CONFIG_BASE_DIRECTORY}/cron/rclone.conf"
mode="$(stat -c %a "${token}" 2>/dev/null || true)"
if [[ ! -f "${token}" || "${mode}" != "600" ]]; then
    log_error        "${INSTALL_WATCHER}" "install.token-google-drive-absent-or-mode-different-of-6" "${token}"
fi
log_success      "${INSTALL_WATCHER}" "install.rclone-installed"
