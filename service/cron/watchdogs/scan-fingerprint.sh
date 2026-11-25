#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/scan-fingerprint.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Compare file digests with the saved stamp and alert when they differ.
# Note       : The stamp lives under the product cron directory.
# Note       : The opening visit stores the stamp and stays silent.
# Note       : The refresh argument stores the current digests and sends no alert.
# -----------------------------------------------------------------------------


read_scan_run_directory() {
    local candidate="" line=""
    for candidate in \
        "${BASE:-}/config/service/clamav/scan.conf" \
        "${CONFIG_BASE_DIRECTORY:-}/config/service/clamav/scan.conf" \
        "${INSTALL_DIRECTORY:-}/config/service/clamav/scan.conf"; do
        [[ -n "${candidate}" && -f "${candidate}" ]] || continue
        while IFS= read -r line || [[ -n "${line}" ]]; do
            case "${line}" in
                run-directory=*)
                    printf '%s\n' "${line#run-directory=}"
                    return 0
                    ;;
            esac
        done <"${candidate}"
    done
    printf '%s\n' "/run/liltress-workstation"
}

# The first existing list is printed.
locate_fingerprint_list() {
    local candidate=""
    for candidate in \
        "${BASE}/config/service/integrity/paths.list" \
        "${CONFIG_BASE_DIRECTORY:-}/config/service/integrity/paths.list" \
        "${INSTALL_DIRECTORY:-}/config/service/integrity/paths.list"; do
        if [[ -f "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    return 1
}

# One sha256sum line per present file.
collect_fingerprint_lines() {
    local list="$1"
    local path=""
    while read -r path; do
        [[ -n "${path}" && "${path}" != \#* && -f "${path}" ]] || continue
        sha256sum -- "${path}"
    done <"${list}" | sort
}

# The runtime stamp path is printed.
get_fingerprint_stamp() {
    if declare -F get_watchdog_runtime_file >/dev/null 2>&1; then
        get_watchdog_runtime_file "${BASE}" integrity.sha256
        return 0
    fi
    printf '%s\n' "${BASE}/cron/integrity.sha256"
}

# Current hashes replace the stamp.
write_fingerprint_stamp() {
    local current="$1"
    local stamp="$2"
    mkdir -p -- "$(dirname -- "${stamp}")"
    cat "${current}" >"${stamp}"
    chmod 600 "${stamp}"
}

# Install stores the files that this run already wrote.
refresh_fingerprint_stamp() {
    local list="" current="" stamp="" run_directory=""
    list="$(locate_fingerprint_list)" || return 0
    run_directory="$(read_scan_run_directory)"
    if ! install -d -m 755 "${run_directory}" 2>/dev/null; then
        run_directory="${BASE}/cron"
        mkdir -p -- "${run_directory}"
    fi
    current="$(mktemp -p "${run_directory}")"
    collect_fingerprint_lines "${list}" >"${current}"
    stamp="$(get_fingerprint_stamp)"
    write_fingerprint_stamp "${current}" "${stamp}"
    rm -f -- "${current}"
    log_info "${INSTALL_WATCHER:-BASH}" "watchdog.recording-of-the-fingerprint"
    log_success "${INSTALL_WATCHER:-BASH}" "watchdog.fingerprint-stored"
}

fingerprint_scan_01_run_01_run() {
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
    LOG_FILE="${LOG_DIR}/integrity-${STAMP}.log"
    ALERT_FILE="${ALERT_DIR}/integrity-${STAMP}.txt"
    if ! declare -F log_pass >/dev/null 2>&1; then
        log_pass() { printf '%s\n' "$*"; }
    fi
}

fingerprint_scan_01_run_02_refresh() {
    if [[ "${1:-}" == "refresh" ]]; then
        refresh_fingerprint_stamp
        exit 0
    fi
    list="$(locate_fingerprint_list || true)"
    if [[ -z "${list}" ]]; then
        log_pass "$(get_text watchdog.list-of-integrity-absent)"
        exit 0
    fi
    run_directory="$(read_scan_run_directory)"
    if ! install -d -m 755 "${run_directory}" 2>/dev/null; then
        run_directory="${BASE}/cron"
        mkdir -p -- "${run_directory}"
    fi
    current="$(mktemp -p "${run_directory}")"
    trap 'rm -f "${current}"' EXIT
    stamp="$(get_fingerprint_stamp)"
    collect_fingerprint_lines "${list}" >"${current}"
    if [[ ! -s "${stamp}" ]]; then
        write_fingerprint_stamp "${current}" "${stamp}"
        log_pass "$(get_text watchdog.initial-fingerprint-written)"
        exit 0
    fi
    if cmp -s "${stamp}" "${current}"; then
        log_pass "$(get_text watchdog.integrity-unchanged)"
        exit 0
    fi
    comm -3 "${stamp}" "${current}" >>"${LOG_FILE}" || true
    write_fingerprint_stamp "${current}" "${stamp}"
    TITLE="$(get_text alert.mail.integrity.title)"
}

fingerprint_scan_01_run_03_get() {
    if declare -F get_mail_service_label >/dev/null 2>&1; then
        MAIL_SERVICE="$(get_mail_service_label fingerprint)"
    else
        MAIL_SERVICE="Fingerprint"
    fi
    export TITLE MAIL_SERVICE
    MODULE_NAME="fingerprint"
    log_alert "$(get_text watchdog.integrity-fingerprint-changed)"
    exit 0
}

fingerprint_scan_01_run_04_run() {
    fingerprint_scan_01_run_01_run "$@"
    fingerprint_scan_01_run_02_refresh "$@"
    fingerprint_scan_01_run_03_get "$@"
}

fingerprint_scan_01_run_04_run "$@"
