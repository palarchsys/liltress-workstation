#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/clamav.sh
# Updated at : 2026-11-11
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


get_clamav_kind() {
    python3 "$(locate_python_dir)/clamav-kind.py" "${1:-}"
}

invoke_clamav() {
    if [[ "${CLAM_MODE:-scan}" == "daemon" ]]; then
        run_limited clamdscan --fdpass --infected --no-summary -- "$@"
    else
        clamscan --infected --no-summary -- "$@"
    fi
}

scan_clamav_batch() {
    local status=0 signal=0 streak=0 path errexit=0 tool="clamscan"
    [[ "$#" -gt 0 ]] || return 0
    if [[ "${CLAM_MODE:-scan}" == "daemon" ]]; then
        tool="clamdscan"
    fi
    case $- in
        *e*) errexit=1 ;;
    esac
    set +e
    invoke_clamav "$@"
    status=$?
    if [[ "${errexit}" -eq 1 ]]; then
        set -e
    fi
    if [[ "${status}" -lt 128 ]]; then
        return 0
    fi
    streak=0
    for path in "$@"; do
        set +e
        invoke_clamav "${path}"
        status=$?
        if [[ "${errexit}" -eq 1 ]]; then
            set -e
        fi
        if [[ "${status}" -ge 128 ]]; then
            signal=$((status - 128))
            printf '%s planté signal %s sur %s\n' "${tool}" "${signal}" "${path}"
            streak=$((streak + 1))
            if [[ "${streak}" -ge 2 ]]; then
                printf '%s planté signal %s, contrôle arrêté\n' "${tool}" "${signal}"
                CLAM_STOP=1
                return 0
            fi
        else
            streak=0
        fi
    done
    return 0
}

list_clamav_scan() {
    local file_list="$1"
    local path batch_max
    local -a batch=()
    batch_max="${CLAM_BATCH:-80}"
    CLAM_STOP=0
    while IFS= read -r -d '' path || [[ -n "${path}" ]]; do
        [[ -n "${path}" ]] || continue
        batch+=("${path}")
        if [[ "${#batch[@]}" -eq "${batch_max}" ]]; then
            scan_clamav_batch "${batch[@]}" || true
            batch=()
            [[ "${CLAM_STOP}" == 1 ]] && break
        fi
    done < "${file_list}"
    if [[ "${#batch[@]}" -gt 0 && "${CLAM_STOP}" != 1 ]]; then
        scan_clamav_batch "${batch[@]}" || true
    fi
    return 0
}

report_clamav() {
    local crashed=0 signal phrase log
    log="${LOG_FILE:-${LOG:-}}"
    [[ -n "${log}" && -f "${log}" ]] || return 1
    crashed="$(grep -c 'planté signal .* sur ' "${log}" || true)"
    [[ "${crashed}" -gt 0 ]] || return 1
    signal="$(sed -n 's/.*planté signal \([0-9][0-9]*\).*/\1/p' "${log}" | head -n 1)"
    phrase="$(signal_phrase "${signal}")"
    if grep -q 'contrôle arrêté' "${log}"; then
        log_alert "$(get_text watchdog.clamav-crashed-twice-in-a-row-signal-the-check-s "${signal}" "${phrase}")"
    elif [[ "${crashed}" -eq 1 ]]; then
        log_alert "$(get_text watchdog.clamav-crashed-signal-on-one-file-that-file-was "${signal}" "${phrase}")"
    else
        log_alert "$(get_text watchdog.clamav-crashed-signal-on-files-those-files-were "${signal}" "${phrase}" "${crashed}")"
    fi
    return 0
}
