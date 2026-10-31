#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/behavior.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================
# -----------------------------------------------------------------------------
# Note       : The stamp lives under the Liltress cron directory.
# Note       : The first pass writes the stamp and stays silent.
# -----------------------------------------------------------------------------

set -euo pipefail
W_BASE="${W_BASE:-/opt/liltress-workstation}"
# shellcheck disable=SC1091
source "${W_BASE}/cron/bin/common.sh"
LOG_FILE="${LOG_DIR}/behavior-${STAMP}.log"
ALERT_FILE="${ALERT_DIR}/behavior-${STAMP}.txt"
MODULE_NAME="Auditd"

if ! command -v ausearch >/dev/null 2>&1; then
    log_pass "$(get_text watchdog.ausearch-absent)"
    exit 0
fi

stamp="${W_BASE}/cron/behavior.stamp"

record_behavior_stamp() {
    local moment
    moment="$(date '+%m/%d/%Y %T')"
    install -d -m 750 "${W_BASE}/cron"
    printf '%s\n' "${moment}" > "${stamp}"
    chmod 600 "${stamp}"
}

if [[ ! -s "${stamp}" ]] || ! grep -Eq '^[0-9]{2}/[0-9]{2}/[0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2}$' "${stamp}"; then
    record_behavior_stamp
    log_pass "$(get_text watchdog.initial-rep-re-written)"
    exit 0
fi

install -d -m 755 /run/liltress-workstation
found="$(mktemp -p /run/liltress-workstation)"
trap 'rm -f "${found}"' EXIT
start="$(head -n 1 "${stamp}")"
set +e
ausearch -k exec-tmp -ts "${start}" -i > "${found}" 2>>"${LOG_FILE}"
status=$?
set -e
record_behavior_stamp
if [[ "${status}" -ne 0 ]] || ! grep -q 'exec-tmp' "${found}"; then
    log_pass "$(get_text watchdog.no-execution-temporary)"
    exit 0
fi
head -n 40 "${found}" >> "${LOG_FILE}"
log_alert "$(get_text watchdog.execution-since-a-directory-temporary)"
exit 0
