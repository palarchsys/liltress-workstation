#!/usr/bin/env bash
# =============================================================================
# File       : service/rngd/install.sh
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
run_silent_apt   "${INSTALL_WATCHER}" "install -y rng-tools-debian" "install.rngd.error"
log_info         "${INSTALL_WATCHER}" "install.configuration-of-rng-tools-debian-hwrng-if-prese"
{
    echo "$(get_text install.liltress-workstation-lynis-cryp-8004)"
    echo "$(get_text install.hrngdevice-dev-hwrng)"
} > /etc/default/rng-tools-debian
chmod 644 /etc/default/rng-tools-debian
run_optional     "${INSTALL_WATCHER}" "install.rngd.error" systemctl enable rng-tools-debian
run_optional     "${INSTALL_WATCHER}" "install.rngd.error" systemctl restart rng-tools-debian.service
if systemctl is-active --quiet rng-tools-debian && pgrep -x rngd >/dev/null; then
    log_success      "${INSTALL_WATCHER}" "install.rngd-enabled"
else
    log_info         "${INSTALL_WATCHER}" "install.no-hwrng-exploitable-entropy-via-haveged-ok-desk"
fi
