#!/usr/bin/env bash
# =============================================================================
# File       : service/postfix/install.sh
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

log_subtitle     "${INSTALL_WATCHER}" "install.installation-of-postfix"
log_info         "${INSTALL_WATCHER}" "install.installation-of-postfix-send-only-internet-site"
debconf_tmp="$(mktemp)"
sed "s|__HOSTNAME__|$(hostname -f)|g" "$(locate_config_file postfix/debconf.conf)" | grep -v '^#' > "${debconf_tmp}"
run_silent       "${INSTALL_WATCHER}" "install.postfix.error" debconf-set-selections "${debconf_tmp}"
rm -f "${debconf_tmp}"
run_silent_apt   "${INSTALL_WATCHER}" "install --no-install-recommends -y postfix mailutils" "install.postfix.error"
run_silent       "${INSTALL_WATCHER}" "install.postfix.error" systemctl enable postfix
log_success      "${INSTALL_WATCHER}" "install.postfix-installed-2"
