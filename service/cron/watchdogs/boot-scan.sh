#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/boot-scan.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

set -euo pipefail
W_BASE="${W_BASE:-/opt/liltress-workstation}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${W_BASE}/cron/bin/common.sh"
LOG_FILE="${LOG_DIR}/boot-scan-${STAMP}.log"
ALERT_FILE="${ALERT_DIR}/boot-scan-${STAMP}.txt"
: > "${LOG_FILE}"

run_check() {
    local script="$1"
    local label="$2"
    local status=0
    if [[ ! -x "${HERE}/${script}" ]]; then
        return 0
    fi
    set +e
    bash "${HERE}/${script}"
    status=$?
    set -e
    if [[ "${status}" -ne 0 ]]; then
        log_alert "$(get_crash_sentence "${label}" "${status}")"
    fi
}

run_check apply-scan-skip.sh "préparation des exclusions"
run_check aide.sh "AIDE"
run_check integrity.sh "intégrité"
run_check rkhunter.sh "rkhunter"
run_check behavior.sh "audit"
run_check chkrootkit.sh "chkrootkit"
run_check clamav.sh "ClamAV"
run_check debsums.sh "debsums"
if [[ -x "${W_BASE}/cron/bin/egress-table.sh" ]]; then
    bash "${W_BASE}/cron/bin/egress-table.sh" || true
fi
run_check egress-watch.sh "journal sortant"
