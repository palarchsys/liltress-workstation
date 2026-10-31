#!/usr/bin/env bash
# =============================================================================
# File       : service/rkhunter/init-db.sh
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

log_subtitle "${INSTALL_WATCHER}" "log.baseline-rkhunter"
log_info "${INSTALL_WATCHER}" "log.record-of-the-baseline-rkhunter"
rk_out=""
rk_rc=0
rk_out=$(rkhunter --update --nocolors 2>&1) || rk_rc=$?
case "${rk_rc}" in
    0|2) ;;
    *) log_warn "${INSTALL_WATCHER}" "log.rkhunter-update-rc-continued" "${rk_rc}" "${rk_out}";;
esac

if [[ ( "${rk_rc}" -eq 0 || "${rk_rc}" -eq 2 ) && -x "${G_CONFIG_BASE_DIRECTORY}/cron/bin/record-mirrors.sh" ]]; then
    W_BASE="${G_CONFIG_BASE_DIRECTORY}" bash "${G_CONFIG_BASE_DIRECTORY}/cron/bin/record-mirrors.sh" save || true
fi

run_silent "${INSTALL_WATCHER}" "install.rkhunter.error" rkhunter --propupd
rk_tmp="/var/lib/rkhunter/tmp"
if [[ -d "${rk_tmp}" ]]; then
    cp -f -p /etc/passwd "${rk_tmp}/passwd"
    cp -f -p /etc/group "${rk_tmp}/group"
fi
log_success "${INSTALL_WATCHER}" "log.baseline-rkhunter-saved"
