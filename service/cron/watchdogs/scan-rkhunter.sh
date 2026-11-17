#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/scan-rkhunter.sh
# Updated at : 2026-11-17
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Run rkhunter --check and alert when warnings remain.
# Note       : The mirror update is a separate refresh.
# -----------------------------------------------------------------------------


read_spare_names() {
    local candidate="" line=""
    SPARE_NAMES=()
    for candidate in \
        "${BASE:-}/config/watchdog/spare.list" \
        "${CONFIG_BASE_DIRECTORY:-}/config/watchdog/spare.list" \
        "${INSTALL_DIRECTORY:-}/config/watchdog/spare.list"; do
        [[ -n "${candidate}" && -f "${candidate}" ]] || continue
        while IFS= read -r line || [[ -n "${line}" ]]; do
            [[ -z "${line}" || "${line}" == \#* ]] && continue
            SPARE_NAMES+=("${line}")
        done <"${candidate}"
        return 0
    done
    SPARE_NAMES=(systemd sshd unbound fail2ban)
}

ensure_rkhunter_allows() {
    local rk_local="/etc/rkhunter.conf.local"
    local allow=""
    touch "${rk_local}"
    for allow in '/dev/shm/*' '/dev/shm/*/*' '/dev/shm/*/*/*' '/dev/log'; do
        if ! grep -qxF "ALLOWDEVFILE=${allow}" "${rk_local}"; then
            printf 'ALLOWDEVFILE=%s\n' "${allow}" >>"${rk_local}"
        fi
    done
}

set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/common.sh"
LOG_FILE="${LOG_DIR}/rkhunter-${STAMP}.log"
ALERT_FILE="${ALERT_DIR}/rkhunter-${STAMP}.txt"
if ! command -v rkhunter >/dev/null; then
    log_pass "$(get_text watchdog.rkhunter-absent-skip)"
    exit 0
fi
ensure_rkhunter_allows
read_spare_names
set +e
# A stuck read on a pty must not hold the rest of the pass.
run_limited timeout --signal=TERM 900 rkhunter --check --skip-keypress --report-warnings-only --nocolors >>"${LOG_FILE}" 2>&1
check_rc=$?
set -e
CONFIRMED_COUNT=0
confirmed_tmp="$(mktemp)"
record_quarantine_log rkhunter "${LOG_FILE}" "${SPARE_NAMES[@]}" >"${confirmed_tmp}" || true
if [[ -s "${confirmed_tmp}" ]]; then
    cat "${confirmed_tmp}" >>"${LOG_FILE}"
fi
rm -f "${confirmed_tmp}"
if [[ "${check_rc}" -ge 128 ]]; then
    log_alert "$(get_crash_sentence "rkhunter" "${check_rc}")"
elif [[ "${check_rc}" -ne 0 || "${CONFIRMED_COUNT:-0}" -gt 0 ]]; then
    if [[ "${check_rc}" -eq 1 && "${CONFIRMED_COUNT:-0}" -eq 0 ]]; then
        set_rkhunter_note || true
        RKHUNTER_REFRESH=1 \
            log_alert "$(get_text watchdog.rkhunter-warnings-see "${LOG_FILE}")"
    else
        log_alert "$(get_text watchdog.rkhunter-warnings-see "${LOG_FILE}")"
    fi
else
    log_pass "rkhunter OK"
fi
exit 0
