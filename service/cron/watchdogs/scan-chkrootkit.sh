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


source_python_boot() {
    local dir hops
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    hops=0
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        if [[ -f "${dir}/core/boot/python.sh" ]]; then
            # shellcheck disable=SC1090
            source "${dir}/core/boot/python.sh"
            return 0
        fi
        if [[ -f "${dir}/share/core/boot/python.sh" ]]; then
            # shellcheck disable=SC1090
            source "${dir}/share/core/boot/python.sh"
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

source_python_boot

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

run_scan_chkrootkit_part_01() {
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

run_scan_chkrootkit_part_02() {
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
        python3 "$(locate_python_dir)/chkrootkit-filter.py" server "${RAW}" "${LOG_FILE}" "${IGNORE}" || true
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
        python3 "$(locate_python_dir)/chkrootkit-filter.py" workstation "${LOG_FILE}" "${IGNORE}" "${LOCAL_IGNORE}" "$1"
        return 0
    fi
    python3 "$(locate_python_dir)/chkrootkit-filter.py" workstation "${LOG_FILE}" "${IGNORE}" "${LOCAL_IGNORE}"
}

run_scan_chkrootkit_part_03() {
    local fragment=""
    if [[ "${rc}" -ge 128 ]]; then
        log_alert "$(get_crash_sentence "chkrootkit" "${rc}")"
        crashed=1
    fi
    fragment="$(read_chkrootkit_fragment)"
    if [[ "${HOST_MODE}" != "server" && (-f "${IGNORE}" || -f "${LOCAL_IGNORE}" || -n "${fragment}") ]]; then
        run_chkrootkit_filter "${fragment}"
    fi
    CONFIRMED_COUNT=0
    confirmed_tmp="$(mktemp)"
    record_quarantine_log chkrootkit "${LOG_FILE}" "${SPARE_NAMES[@]}" >"${confirmed_tmp}" || true
    if [[ -s "${confirmed_tmp}" ]]; then
        cat "${confirmed_tmp}" >>"${LOG_FILE}"
    fi
    rm -f "${confirmed_tmp}"
}

run_scan_chkrootkit_part_04() {
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

run_scan_chkrootkit_part_05() {
    run_scan_chkrootkit_part_01 "$@"
    run_scan_chkrootkit_part_02 "$@"
    run_scan_chkrootkit_part_03 "$@"
    run_scan_chkrootkit_part_04 "$@"
}

run_scan_chkrootkit_part_05 "$@"
