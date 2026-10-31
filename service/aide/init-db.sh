#!/usr/bin/env bash
# =============================================================================
# File       : service/aide/init-db.sh
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

log_subtitle "${INSTALL_WATCHER}" "log.baseline-help"
log_info "${INSTALL_WATCHER}" "log.the-calculation-of-the-fingerprints-can-take-sev"
log_info "${INSTALL_WATCHER}" "log.the-detail-stays-in-the-journal-not-in-the-termi"

log_info "${INSTALL_WATCHER}" "log.record-of-the-baseline-help"
aide_log="${G_LOG_DIR:-/var/log/liltress-workstation}/aide-init.log"
mkdir -p "$(dirname "${aide_log}")"

rm -f /var/lib/aide/aide.db.new /var/lib/aide/aide.db.new.gz

if ! aide --config="/etc/aide/aide.conf" --init >"${aide_log}" 2>&1; then
    log_warn "${INSTALL_WATCHER}" "log.help-init-a-returned-an-error-detail" "${aide_log}"
fi
if [[ -f /var/lib/aide/aide.db.new.gz ]]; then
    mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz

    ln -sfn /var/lib/aide/aide.db.gz /var/lib/aide/aide.db
elif [[ -f /var/lib/aide/aide.db.new ]]; then
    mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
else
    log_error "${INSTALL_WATCHER}" "log.base-help-not-generated-help-db-new-not-found-de" "${aide_log}"
fi
log_success "${INSTALL_WATCHER}" "log.baseline-help-saved"
