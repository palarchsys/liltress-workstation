#!/usr/bin/env bash
# =============================================================================
# File       : service/rkhunter/configure.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root
get_current_user
ACCOUNT_USER="${CURRENT_USER}"
export ACCOUNT_USER

log_info         "${INSTALL_WATCHER}" "configure.configuration-of-rkhunter-2"
envsubst '$ACCOUNT_USER' < "$(locate_config_file rkhunter/rkhunter.conf.local)" > /etc/rkhunter.conf.local
chmod 644 /etc/rkhunter.conf.local
log_success      "${INSTALL_WATCHER}" "configure.rkhunter-conf-local-installed"

if grep -qE '^[[:space:]]*WEB_CMD=' /etc/rkhunter.conf; then
    sed -i 's|^[[:space:]]*WEB_CMD=.*|WEB_CMD=""|' /etc/rkhunter.conf
fi

log_info         "${INSTALL_WATCHER}" "configure.base-rkhunter-propupd-after-the-purge-of-the-pac"
install -d -m 755 "${CONFIG_BASE_DIRECTORY}/bin"
install -m 755 \
    "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/refresh-db.sh" \
    "${CONFIG_BASE_DIRECTORY}/bin/rkhunter-refresh-db.sh"
