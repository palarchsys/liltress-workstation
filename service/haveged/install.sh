#!/usr/bin/env bash
# =============================================================================
# File       : service/haveged/install.sh
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

log_subtitle     "${INSTALL_WATCHER}" "install.entropy-haveged-rng-tools-debian"
log_info         "${INSTALL_WATCHER}" "install.installation-of-haveged-and-of-rng-tools-debian"
run_silent_apt   "${INSTALL_WATCHER}" "install -y haveged" "install.haveged.error"
run_silent       "${INSTALL_WATCHER}" "install.haveged.error" systemctl enable --now haveged
if ! systemctl is-active --quiet haveged; then
    log_warn         "${INSTALL_WATCHER}" "install.haveged-installed-but-inactive-2"
else
    log_success      "${INSTALL_WATCHER}" "install.haveged-enabled"
fi
