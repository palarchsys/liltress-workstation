#!/usr/bin/env bash
# =============================================================================
# File       : service/auditd/install.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Install the audit daemon and reload its units.
# -----------------------------------------------------------------------------


INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info "${INSTALL_WATCHER}" "install.installation-of-auditd"
run_silent_apt "${INSTALL_WATCHER}" "install -y auditd audispd-plugins" "install.auditd.error"
log_success "${INSTALL_WATCHER}" "install.auditd-installed"

log_info "${INSTALL_WATCHER}" "install.inclusion-of-the-units-possibly-added"
run_silent "${INSTALL_WATCHER}" "install.auditd.error" systemctl daemon-reload
log_success "${INSTALL_WATCHER}" "install.systemd-reloaded"
