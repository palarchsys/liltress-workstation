#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/refresh-rkhunter-db.sh
# Updated at : 2026-11-17
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Update rkhunter mirrors and store their digest.
# Note       : Codes 0 and 2 still store the mirror digest.
# Note       : Property data is left unchanged.
# -----------------------------------------------------------------------------


set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/common.sh"
LOG_FILE="${LOG_DIR}/rkhunter-refresh-${STAMP}.log"
ALERT_FILE="${ALERT_DIR}/rkhunter-refresh-${STAMP}.txt"
if ! command -v rkhunter >/dev/null; then
    log_pass "$(get_text watchdog.rkhunter-absent-skip)"
    exit 0
fi
mirrors="${HERE}/record-mirrors.sh"
if [[ -x "${BASE}/service/cron/watchdogs/record-mirrors.sh" ]]; then
    mirrors="${BASE}/service/cron/watchdogs/record-mirrors.sh"
fi
if [[ -x "${mirrors}" ]]; then
    if ! bash "${mirrors}" check; then
        log_alert "$(get_text watchdog.mirrors-dat-changed-outside-rkhunter-update)"
    fi
fi
rk_rc=0
rkhunter --update --nocolors >>"${LOG_FILE}" 2>&1 || rk_rc=$?
if [[ "${rk_rc}" -eq 0 || "${rk_rc}" -eq 2 ]]; then
    bash "${mirrors}" save || true
fi
if [[ "${rk_rc}" -ge 128 ]]; then
    log_alert "$(get_crash_sentence "rkhunter" "${rk_rc}")"
fi
exit 0
