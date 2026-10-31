#!/usr/bin/env bash
# =============================================================================
# File       : service/rkhunter/configure.sh
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
get_current_user
W_ACCOUNT_USER="${CURRENT_USER}"
export W_ACCOUNT_USER

log_subtitle     "${INSTALL_WATCHER}" "configure.configuration-rkhunter"
log_info         "${INSTALL_WATCHER}" "configure.configuration-of-rkhunter-2"
envsubst '$W_ACCOUNT_USER' < "$(locate_config_file rkhunter/rkhunter.conf.local)" > /etc/rkhunter.conf.local
chmod 644 /etc/rkhunter.conf.local
log_success      "${INSTALL_WATCHER}" "configure.rkhunter-conf-local-installed"

if grep -qE '^[[:space:]]*WEB_CMD=' /etc/rkhunter.conf; then
    sed -i 's|^[[:space:]]*WEB_CMD=.*|WEB_CMD=""|' /etc/rkhunter.conf
fi

log_info         "${INSTALL_WATCHER}" "configure.base-rkhunter-propupd-after-the-purge-of-the-pac"
install -d -m 755 "${G_CONFIG_BASE_DIRECTORY}/bin"
install -m 755 \
    "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/refresh-db.sh" \
    "${G_CONFIG_BASE_DIRECTORY}/bin/rkhunter-refresh-db.sh"
