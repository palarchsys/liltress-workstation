#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/scan-auditd.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Alert on a temporary execution or an abnormal audit event.
# Note       : Events from the product cron tree are left out.
# Note       : A signal keeps the stamp so the next pass rereads the window.
# -----------------------------------------------------------------------------


read_ausearch_bin() {
    if command -v ausearch >/dev/null 2>&1; then
        command -v ausearch
        return 0
    fi
    if [[ -x /usr/sbin/ausearch ]]; then
        printf '%s\n' "/usr/sbin/ausearch"
        return 0
    fi
    return 1
}

record_audit_stamp() {
    local moment=""
    moment="$(date '+%m/%d/%Y %T')"
    mkdir -p -- "$(dirname -- "${stamp}")"
    printf '%s\n' "${moment}" >"${stamp}"
    chmod 600 "${stamp}"
}

check_audit_line_own() {
    local line="$1"
    local root="${BASE}/service/cron/watchdogs"
    local cron="${BASE}/cron/bin"
    [[ "${line}" == *"cwd=${root}"* ]] && return 0
    [[ "${line}" == *"cwd=${cron}"* ]] && return 0
    [[ "${line}" == *"exe=${root}/"* ]] && return 0
    return 1
}

check_audit_line_exec() {
    [[ "$1" == *exec-tmp* ]] && return 0
    return 1
}

check_audit_line_anom() {
    local line="$1"
    [[ "${line}" == *type=ANOM_* ]] && return 0
    [[ "${line}" == *type=USER_LOGIN* && "${line}" == *res=failed* ]] && return 0
    [[ "${line}" == *type=USER_AUTH* && "${line}" == *res=failed* ]] && return 0
    return 1
}

collect_audit_hits() {
    local line=""
    : >"${kept}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        check_audit_line_own "${line}" && continue
        if check_audit_line_exec "${line}" || check_audit_line_anom "${line}"; then
            printf '%s\n' "${line}" >>"${kept}"
        fi
    done <"${found}"
}

invoke_ausearch() {
    local dest="$1"
    shift
    if declare -F run_limited >/dev/null 2>&1; then
        run_limited "$@" >"${dest}" 2>&1
        return $?
    fi
    "$@" >"${dest}" 2>&1
}

read_audit_window() {
    local bin="$1"
    local start="$2"
    local status=0
    set +e
    invoke_ausearch "${found}" "${bin}" -k exec-tmp -ts "${start}" -i
    status=$?
    set -e
    if [[ "${status}" -ge 128 ]]; then
        cat "${found}" >"${LOG_FILE}"
        log_alert "$(get_crash_sentence "audit" "${status}")"
        exit 0
    fi
    set +e
    invoke_ausearch "${extra}" "${bin}" -ts "${start}" -i || true
    set -e
    cat "${extra}" >>"${found}"
}

finish_audit_window() {
    collect_audit_hits
    record_audit_stamp
    if grep -q 'exec-tmp' "${kept}"; then
        head -n 40 "${kept}" >>"${LOG_FILE}"
        log_alert "$(get_text watchdog.execution-since-a-directory-temporary)"
        return 0
    fi
    if [[ -s "${kept}" ]]; then
        head -n 80 "${kept}" >>"${LOG_FILE}"
        log_alert "$(get_text log.events-of-audit-abnormal-ausearch)"
        return 0
    fi
    printf '%s\n' "$(get_text watchdog.no-execution-temporary)"
}

auditd_scan_01_run_01_get() {
    set -euo pipefail
    HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -r "${HERE}/watchdog.conf" ]]; then
        # shellcheck disable=SC1091
        source "${HERE}/watchdog.conf"
    fi
    if [[ -z "${BASE:-}" && -z "${CONFIG_BASE_DIRECTORY:-}" && -n "${CONFIG_BASE_DIRECTORY+x}" ]]; then
        exit 0
    fi
    # shellcheck disable=SC1091
    source "${HERE}/common.sh"
    if [[ -z "${BASE:-}" ]]; then
        BASE="${CONFIG_BASE_DIRECTORY:-/opt/liltress-workstation}"
    fi
    STAMP="${STAMP:-$(date +%Y%m%d-%H%M%S)}"
    LOG_DIR="${LOG_DIR:-${BASE}/cron/security_logs}"
    ALERT_DIR="${ALERT_DIR:-${BASE}/cron/alerts}"
    mkdir -p -- "${LOG_DIR}" "${ALERT_DIR}"
    LOG_FILE="${LOG_DIR}/auditd-${STAMP}.log"
    ALERT_FILE="${ALERT_DIR}/auditd-${STAMP}.txt"
    MODULE_NAME="Auditd"
    if declare -F get_watchdog_runtime_file >/dev/null 2>&1; then
        stamp="$(get_watchdog_runtime_file "${BASE}" behavior.stamp)"
    else
        stamp="${BASE}/cron/behavior.stamp"
    fi
    ausearch_bin="$(read_ausearch_bin || true)"
}

auditd_scan_01_run_02_get() {
    if [[ -z "${ausearch_bin}" ]]; then
        printf '%s\n' "$(get_text watchdog.ausearch-absent)"
        exit 0
    fi
    if [[ ! -s "${stamp}" ]] || ! grep -Eq '^[0-9]{2}/[0-9]{2}/[0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2}$' "${stamp}"; then
        record_audit_stamp
        printf '%s\n' "$(get_text watchdog.initial-rep-re-written)"
        exit 0
    fi
    found="$(mktemp)"
    extra="$(mktemp)"
    kept="$(mktemp)"
    trap 'rm -f "${found}" "${extra}" "${kept}"' EXIT
    start="$(head -n 1 "${stamp}")"
    read_audit_window "${ausearch_bin}" "${start}"
    finish_audit_window
    exit 0
}

auditd_scan_01_run_03_run() {
    auditd_scan_01_run_01_get "$@"
    auditd_scan_01_run_02_get "$@"
}

auditd_scan_01_run_03_run "$@"
