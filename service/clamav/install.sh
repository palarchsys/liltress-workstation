#!/usr/bin/env bash
# =============================================================================
# File       : service/clamav/install.sh
# Updated at : 2026-11-07
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info         "${INSTALL_WATCHER}" "install.installation-of-clamav"
run_silent_apt   "${INSTALL_WATCHER}" "install -y clamav clamav-daemon clamav-freshclam" "install.clamav.error"
if ! check_workstation; then
    ensure_directory /var/lib/clamav/quarantine 750 clamav clamav
    ensure_directory /var/lib/clamav/tmp 700 clamav clamav
fi
log_success      "${INSTALL_WATCHER}" "install.clamav-installed"

log_info         "${INSTALL_WATCHER}" "install.inclusion-of-the-units-possibly-added"
run_silent       "${INSTALL_WATCHER}" "install.clamav.error" systemctl daemon-reload
log_success      "${INSTALL_WATCHER}" "install.systemd-reloaded"
