#!/usr/bin/env bash
# =============================================================================
# File       : verify/summary.sh
# Updated at : 2026-11-07
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

status_file="${INSTALL_LOG_DIR:-.}/verify-status"
if [[ ! -f "${status_file}" ]]; then
    log_error "${INSTALL_WATCHER}" "verify.workstation.info.5" "bilan de vérification absent"
fi

PASS=0
WARN=0
FAIL=0
REPORT=""
# shellcheck disable=SC1090
source "${status_file}"

log_check_count() {
    local label="$1"
    local value="$2"
    local line=""
    printf -v line '%-15s: %s' "${label}" "${value}"
    log_info "${INSTALL_WATCHER}" "verify.workstation.info.5" "${line}"
}

log_check_count "$(get_text log.check-success)" "${PASS}"
log_check_count "$(get_text log.check-warnings)" "${WARN}"
log_check_count "$(get_text log.check-fails)" "${FAIL}"
if [[ "${FAIL}" -eq 0 ]]; then
    log_success "${INSTALL_WATCHER}" "log.check-workstation-ok"
else
    log_error "${INSTALL_WATCHER}" "log.check-failure-s" "${FAIL}"
fi
