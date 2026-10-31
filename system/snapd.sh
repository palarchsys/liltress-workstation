#!/usr/bin/env bash
# =============================================================================
# File       : system/snapd.sh
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

log_subtitle "${INSTALL_WATCHER}" "log.snapd"
log_info "${INSTALL_WATCHER}" "log.installation-of-snapd"
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export APT_LISTCHANGES_FRONTEND=none

rm -f /etc/apt/preferences.d/no-snap.pref
apt-mark unhold snapd >/dev/null 2>&1 || true
apt-mark unhold firefox >/dev/null 2>&1 || true
if ! dpkg-query -W -f '${Status}' snapd 2>/dev/null | grep -q 'install ok'; then
    run_silent_apt "${INSTALL_WATCHER}" "install -y snapd" "install.snapd.error"
fi

log_success "${INSTALL_WATCHER}" "log.snapd-installed"
