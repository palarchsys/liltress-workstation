#!/usr/bin/env bash
# =============================================================================
# File       : script/verify/lynis-audit.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

if ! command -v lynis >/dev/null 2>&1; then
    log_error "${INSTALL_WATCHER}" "verify.workstation.info.5" "lynis absent"
fi

log_info "${INSTALL_WATCHER}" "log.audit-lynis-quick"
lynis audit system --quick --no-colors --auditor liltress-workstation-verify > "${INSTALL_LOG_DIR:-/tmp}/lynis-verify.txt" 2>&1 || true
score="$(awk -F= '/hardening_index=/{print $2}' /var/log/lynis-report.dat 2>/dev/null | tail -1)"
if [[ ! "${score}" =~ ^[0-9]+$ ]]; then
    log_error "${INSTALL_WATCHER}" "verify.workstation.info.5" "score Lynis illisible"
fi
chmod 640 /var/log/lynis.log /var/log/lynis-report.dat 2>/dev/null || true
if [[ "${score}" -ge "${LYNIS_MIN_SCORE}" ]]; then
    if [[ "${INSTALL_WATCHER}" == "GO" ]]; then
        log_success "${INSTALL_WATCHER}" "log.ok-3" "Lynis ${score} ≥ ${LYNIS_MIN_SCORE}"
    else
        note_bash success "Lynis ${score} ≥ ${LYNIS_MIN_SCORE}"
    fi
else
    while IFS= read -r line; do
        note_bash info "Lynis ${line}"
    done < <(awk -F= '/^warning\[\]=/{print $2}' /var/log/lynis-report.dat 2>/dev/null | head -20 || true)
    log_error "${INSTALL_WATCHER}" "verify.workstation.info.5" "Lynis ${score} < ${LYNIS_MIN_SCORE}"
fi
