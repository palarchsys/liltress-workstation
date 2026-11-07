#!/usr/bin/env bash
# =============================================================================
# File       : service/postfix/install.sh
# Updated at : 2026-11-07
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info         "${INSTALL_WATCHER}" "install.preconfiguration-of-postfix"
debconf_tmp="$(mktemp)"
sed "s|__HOSTNAME__|$(hostname -f)|g" "$(locate_config_file postfix/debconf.conf)" | grep -v '^#' > "${debconf_tmp}"
run_silent       "${INSTALL_WATCHER}" "install.postfix.error" debconf-set-selections "${debconf_tmp}"
rm -f "${debconf_tmp}"
log_success      "${INSTALL_WATCHER}" "install.preconfiguration-of-postfix-finished"

log_info         "${INSTALL_WATCHER}" "install.installation-of-postfix"
run_silent_apt   "${INSTALL_WATCHER}" "install --no-install-recommends -y postfix mailutils" "install.postfix.error"
if check_workstation; then
    run_silent "${INSTALL_WATCHER}" "install.postfix.error" systemctl enable postfix
fi
log_success      "${INSTALL_WATCHER}" "install.postfix-installed"

log_info         "${INSTALL_WATCHER}" "install.inclusion-of-the-units-possibly-added"
run_silent       "${INSTALL_WATCHER}" "install.postfix.error" systemctl daemon-reload
log_success      "${INSTALL_WATCHER}" "install.systemd-reloaded"
