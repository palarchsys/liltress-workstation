#!/usr/bin/env bash
# =============================================================================
# File       : service/debsums/install.sh
# Updated at : 2026-11-13
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info         "${INSTALL_WATCHER}" "install.installation-of-debsums"
run_silent_apt   "${INSTALL_WATCHER}" "install -y debsums" "install.debsums.error"
cron_line="$(grep -vE '^[[:space:]]*(#|$)' "$(locate_config_file debsums/check.conf)" | head -1)"
if [[ -z "${cron_line}" ]]; then
    log_error        "${INSTALL_WATCHER}" "install.line-cron-check-not-found"
fi
if [[ -f /etc/default/debsums ]]; then
    sed -i "s/^#*CRON_CHECK=.*/${cron_line}/" /etc/default/debsums
    grep -q '^CRON_CHECK=' /etc/default/debsums || echo "${cron_line}" >> /etc/default/debsums
else
    echo "${cron_line}" > /etc/default/debsums
fi
chmod 644 /etc/default/debsums
log_success      "${INSTALL_WATCHER}" "install.installation-debsums-finished" "${cron_line}"

log_info         "${INSTALL_WATCHER}" "install.inclusion-of-the-units-possibly-added"
run_silent       "${INSTALL_WATCHER}" "install.debsums.error" systemctl daemon-reload
log_success      "${INSTALL_WATCHER}" "install.systemd-reloaded"
