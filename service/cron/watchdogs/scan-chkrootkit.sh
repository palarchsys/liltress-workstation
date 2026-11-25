#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/scan-chkrootkit.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Record confirmed rootkit rows on this host.
# Note       : NetworkManager, wpa_supplicant, and systemd-networkd stay excluded.
# -----------------------------------------------------------------------------


# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../../core/boot/python.sh"

read_host_mode() {
    local candidate="" line=""
    HOST_MODE="workstation"
    for candidate in \
        "${BASE:-}/config/service/watchdog/host.list" \
        "${CONFIG_BASE_DIRECTORY:-}/config/service/watchdog/host.list" \
        "${INSTALL_DIRECTORY:-}/config/service/watchdog/host.list"; do
        [[ -n "${candidate}" && -f "${candidate}" ]] || continue
        line="$(grep -v '^#' "${candidate}" | head -n 1 || true)"
        [[ -n "${line}" ]] && HOST_MODE="${line}"
        return 0
    done
}

read_spare_names() {
    local candidate="" line=""
    SPARE_NAMES=()
    for candidate in \
        "${BASE:-}/config/service/watchdog/spare.list" \
        "${CONFIG_BASE_DIRECTORY:-}/config/service/watchdog/spare.list" \
        "${INSTALL_DIRECTORY:-}/config/service/watchdog/spare.list"; do
        [[ -n "${candidate}" && -f "${candidate}" ]] || continue
        while IFS= read -r line || [[ -n "${line}" ]]; do
            [[ -z "${line}" || "${line}" == \#* ]] && continue
            SPARE_NAMES+=("${line}")
        done <"${candidate}"
        return 0
    done
    SPARE_NAMES=(systemd sshd unbound fail2ban)
}

chkrootkit_scan_01_run_01_locate() {
    set -euo pipefail
    # shellcheck disable=SC1091
    source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"
    LOG_FILE="${LOG_DIR}/chkrootkit-${STAMP}.log"
    ALERT_FILE="${ALERT_DIR}/chkrootkit-${STAMP}.txt"
    HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "${BASE}/core/host/fs.sh" ]]; then
        # shellcheck disable=SC1091
        source "${BASE}/core/host/fs.sh"
    elif [[ -f "${HERE}/../../../core/host/fs.sh" ]]; then
        # shellcheck disable=SC1091
        source "${HERE}/../../../core/host/fs.sh"
    fi
    IGNORE=""
    if declare -F locate_config_file >/dev/null 2>&1; then
        IGNORE="$(locate_config_file service/chkrootkit/patterns.ignore || true)"
    fi
    if [[ ! -f "${IGNORE}" && -f "${HERE}/../../../config/service/chkrootkit/patterns.ignore" ]]; then
        IGNORE="${HERE}/../../../config/service/chkrootkit/patterns.ignore"
    fi
}

chkrootkit_scan_01_run_02_get() {
    if [[ ! -f "${IGNORE}" && -f "${HERE}/chkrootkit.ignore" ]]; then
        IGNORE="${HERE}/chkrootkit.ignore"
    fi
    if [[ ! -f "${IGNORE}" ]]; then
        IGNORE="${BASE}/config/service/chkrootkit/patterns.ignore"
    fi
    LOCAL_IGNORE="${BASE}/cron/chkrootkit.local.ignore"
    if ! command -v chkrootkit >/dev/null; then
        log_pass "$(get_text watchdog.chkrootkit-absent-skip)"
        exit 0
    fi
    read_host_mode
    read_spare_names
    set +e
    if [[ "${HOST_MODE}" == "server" ]]; then
        RAW="${LOG_FILE}.raw"
        sudo /usr/sbin/chkrootkit -x -q 2>&1 | tee "${RAW}" >/dev/null
        rc="${PIPESTATUS[0]}"
        python3 "$(locate_python_directory)/chkrootkit-filter.py" server "${RAW}" "${LOG_FILE}" "${IGNORE}" || true
        rm -f "${RAW}"
    else
        chkrootkit -q -s 'NetworkManager|wpa_supplicant|systemd-networkd' >"${LOG_FILE}" 2>&1
        rc=$?
    fi
    set -e
    crashed=0
}

read_chkrootkit_fragment() {
    local file="${BASE}/config/service/exclusions/generated/chkrootkit.ignore"
    local line
    [[ -f "${file}" ]] || return 0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        case "${line}" in
            "" | \#*) continue ;;
            *)
                printf '%s\n' "${file}"
                return 0
                ;;
        esac
    done <"${file}"
}

run_chkrootkit_filter() {
    if [[ -n "${1:-}" ]]; then
        python3 "$(locate_python_directory)/chkrootkit-filter.py" workstation "${LOG_FILE}" "${IGNORE}" "${LOCAL_IGNORE}" "$1"
        return 0
    fi
    python3 "$(locate_python_directory)/chkrootkit-filter.py" workstation "${LOG_FILE}" "${IGNORE}" "${LOCAL_IGNORE}"
}

# A workstation report is filtered when an ignore list or a fragment exists.
apply_chkrootkit_ignore() {
    local fragment="$1"
    if [[ "${HOST_MODE}" != "server" && (-f "${IGNORE}" || -f "${LOCAL_IGNORE}" || -n "${fragment}") ]]; then
        run_chkrootkit_filter "${fragment}"
    fi
}

chkrootkit_scan_01_run_03_get() {
    local fragment=""
    if [[ "${rc}" -ge 128 ]]; then
        log_alert "$(get_crash_sentence "chkrootkit" "${rc}")"
        crashed=1
    fi
    fragment="$(read_chkrootkit_fragment)"
    apply_chkrootkit_ignore "${fragment}"
    CONFIRMED_COUNT=0
    confirmed_tmp="$(mktemp)"
    record_quarantine_log chkrootkit "${LOG_FILE}" "${SPARE_NAMES[@]}" >"${confirmed_tmp}" || true
    if [[ -s "${confirmed_tmp}" ]]; then
        cat "${confirmed_tmp}" >>"${LOG_FILE}"
    fi
    rm -f "${confirmed_tmp}"
}

chkrootkit_scan_01_run_04_get() {
    if [[ -s "${LOG_FILE}" ]]; then
        if [[ "${CONFIRMED_COUNT:-0}" -eq 0 ]]; then
            CHKROOTKIT_IGNORE=1 \
                log_alert "$(get_text watchdog.chkrootkit-a-produced-a-output-see "${LOG_FILE}")"
        else
            log_alert "$(get_text watchdog.chkrootkit-a-produced-a-output-see "${LOG_FILE}")"
        fi
    elif [[ "${crashed}" -eq 0 ]]; then
        log_pass "$(get_text watchdog.chkrootkit-silencieux-ok)"
    fi
    exit 0
}

chkrootkit_scan_01_run_05_run() {
    chkrootkit_scan_01_run_01_locate "$@"
    chkrootkit_scan_01_run_02_get "$@"
    chkrootkit_scan_01_run_03_get "$@"
    chkrootkit_scan_01_run_04_get "$@"
}

chkrootkit_scan_01_run_05_run "$@"
