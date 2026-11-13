#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/boot-scan.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

set -euo pipefail
BASE="${BASE:-/opt/liltress-workstation}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"
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

if [[ -f "${BASE}/cron/mail.conf" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${BASE}/cron/mail.conf"
    set +a
fi
export BASE
if [[ -x "${HERE}/chain.sh" ]]; then
    set +e
    bash "${HERE}/chain.sh"
    chain_status=$?
    set -e
    if [[ "${chain_status}" -ne 0 ]]; then
        log_alert "$(get_crash_sentence "chaîne" "${chain_status}")"
    fi
fi
run_check apply-scan-skip.sh "préparation des exclusions"
run_check integrity.sh "intégrité"
run_check behavior.sh "audit"
if [[ -x "${BASE}/cron/egress-table.sh" ]]; then
    bash "${BASE}/cron/egress-table.sh" || true
fi
run_check egress-watch.sh "journal sortant"
