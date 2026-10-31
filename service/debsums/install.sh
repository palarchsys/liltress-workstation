#!/usr/bin/env bash
# =============================================================================
# File       : service/debsums/install.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY
G_INSTALL_DIRECTORY="${INSTALL_DIRECTORY}"
export G_INSTALL_DIRECTORY
# shellcheck disable=SC2155
readonly DIR_SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${G_INSTALL_DIRECTORY}/core/lib.sh"
source "${G_INSTALL_DIRECTORY}/config/global.conf"
require_root

log_subtitle     "${INSTALL_WATCHER}" "install.installation-debsums-2"
log_info         "${INSTALL_WATCHER}" "install.installation-of-debsums"
run_silent_apt   "${INSTALL_WATCHER}" "install -y debsums" "install.debsums.error"
install -d -m 755 "${G_CONFIG_BASE_DIRECTORY}/bin"
install -m 755 "${DIR_SCRIPT_PATH}/ignore-log.sh" "${G_CONFIG_BASE_DIRECTORY}/bin/debsums-ignore-log.sh"

cron_line="$(grep -v '^#' "$(locate_config_file debsums/check.conf)" | head -1)"
if [[ -f /etc/default/debsums ]]; then
    if grep -q '^CRON_CHECK=' /etc/default/debsums; then
        sed -i "s/^CRON_CHECK=.*/${cron_line}/" /etc/default/debsums
    else
        printf '%s\n' "${cron_line}" >> /etc/default/debsums
    fi
else
    printf '%s\n' "${cron_line}" > /etc/default/debsums
fi
log_success      "${INSTALL_WATCHER}" "install.debsums-installed"
