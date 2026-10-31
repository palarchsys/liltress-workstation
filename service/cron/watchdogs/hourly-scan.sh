#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/hourly-scan.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================
# -----------------------------------------------------------------------------
# Purpose    : Hourly AIDE, rkhunter, chkrootkit and debsums, in that order.
# Note       : Each script writes its own security log. A clean pass sends no mail.
# -----------------------------------------------------------------------------

set -euo pipefail
W_BASE="${W_BASE:-/opt/liltress-workstation}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${W_BASE}/cron/bin/common.sh"
LOG_FILE="${LOG_DIR}/hourly-scan-${STAMP}.log"
ALERT_FILE="${ALERT_DIR}/hourly-scan-${STAMP}.txt"

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

run_check aide.sh "AIDE"
run_check rkhunter.sh "rkhunter"
run_check chkrootkit.sh "chkrootkit"
run_check debsums.sh "debsums"
