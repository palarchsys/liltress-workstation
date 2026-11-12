#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/debsums.sh
# Updated at : 2026-11-04
# Creator    : palarchsys
# =============================================================================


locate_python_dir() {
    local dir hops=0
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        if [[ -d "${dir}/share/python" ]]; then
            printf '%s\n' "${dir}/share/python"
            return 0
        fi
        if [[ -d "${dir}/python" ]]; then
            printf '%s\n' "${dir}/python"
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

set -euo pipefail
BASE="${BASE:-/opt/liltress-workstation}"
# shellcheck disable=SC1091
source "${BASE}/cron/bin/common.sh"
LOG_FILE="${LOG_DIR}/debsums-${STAMP}.log"
ALERT_FILE="${ALERT_DIR}/debsums-${STAMP}.txt"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
IGNORE="${HERE}/debsums.ignore"
LOCAL_IGNORE="${BASE}/cron/debsums.local.ignore"
if ! command -v debsums >/dev/null; then
    log_pass "$(get_text watchdog.debsums-absent-skip)"
    exit 0
fi
set +e
debsums -s > "${LOG_FILE}" 2>&1
rc=$?
set -e
crashed=0
if [[ "${rc}" -ge 128 ]]; then
    log_alert "$(get_crash_sentence "debsums" "${rc}")"
    crashed=1
fi
python3 "$(locate_python_dir)/debsums-filter.py" workstation "${LOG_FILE}" "${IGNORE}" "${LOCAL_IGNORE}" "${BASE}"
if [[ "${crashed}" -eq 0 && -s "${LOG_FILE}" ]]; then
    summary="$(reset_debsums_log "${LOG_FILE}")"
    if [[ -n "${summary}" ]]; then
        log_alert "${summary}"
    fi
elif [[ "${crashed}" -eq 0 ]]; then
    log_pass "debsums OK"
fi
exit 0
