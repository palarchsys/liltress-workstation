#!/usr/bin/env bash
# =============================================================================
# File       : service/aide/init-db.sh
# Updated at : 2026-11-07
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info "${INSTALL_WATCHER}" "log.the-calculation-of-the-fingerprints-can-take-sev"
log_info "${INSTALL_WATCHER}" "log.the-detail-stays-in-the-journal-not-in-the-termi"

if systemctl cat apt-listchanges.timer >/dev/null 2>&1; then
    systemctl disable --now apt-listchanges.timer >/dev/null 2>&1 || true
    log_info "${INSTALL_WATCHER}" "log.apt-listchanges-timer-stopped-before-the-aide-bas"
fi

log_info "${INSTALL_WATCHER}" "log.record-of-the-baseline-help"
aide_log="${INSTALL_LOG_DIR:-/var/log/${PROJECT_SLUG}}/aide-init.log"
mkdir -p "$(dirname "${aide_log}")"

rm -f /var/lib/aide/aide.db.new /var/lib/aide/aide.db.new.gz

if ! aide --config="/etc/aide/aide.conf" --init >"${aide_log}" 2>&1; then
    log_warn "${INSTALL_WATCHER}" "log.help-init-a-returned-an-error-detail" "${aide_log}"
fi
if [[ -f /var/lib/aide/aide.db.new.gz ]]; then
    mv -f /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
    ln -sfn /var/lib/aide/aide.db.gz /var/lib/aide/aide.db
elif [[ -f /var/lib/aide/aide.db.new ]]; then
    mv -f /var/lib/aide/aide.db.new /var/lib/aide/aide.db
else
    log_error "${INSTALL_WATCHER}" "log.base-help-not-generated-help-db-new-not-found-de" "${aide_log}"
fi
log_success "${INSTALL_WATCHER}" "log.baseline-help-saved"
