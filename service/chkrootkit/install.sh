#!/usr/bin/env bash
# =============================================================================
# File       : service/chkrootkit/install.sh
# Updated at : 2026-11-13
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info         "${INSTALL_WATCHER}" "install.installation-of-chkrootkit"
run_silent_apt   "${INSTALL_WATCHER}" "install -y chkrootkit" "install.chkrootkit.error"
if systemctl cat chkrootkit.timer >/dev/null 2>&1; then
    run_optional "${INSTALL_WATCHER}" "install.chkrootkit.error" systemctl disable --now chkrootkit.timer
    run_optional "${INSTALL_WATCHER}" "install.chkrootkit.error" systemctl mask chkrootkit.timer
fi
ignore_src="$(locate_config_file chkrootkit/patterns.ignore || true)"
if [[ -z "${ignore_src}" || ! -f "${ignore_src}" ]]; then
    log_error        "${INSTALL_WATCHER}" "install.list-chkrootkit-not-found"
fi
log_success      "${INSTALL_WATCHER}" "install.chkrootkit-installed"

log_info         "${INSTALL_WATCHER}" "install.inclusion-of-the-units-possibly-added"
run_silent       "${INSTALL_WATCHER}" "install.chkrootkit.error" systemctl daemon-reload
log_success      "${INSTALL_WATCHER}" "install.systemd-reloaded"
