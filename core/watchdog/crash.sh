#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/crash.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================


signal_phrase() {
    case "$1" in
        6) printf '%s' "$(get_text watchdog.signal.abort)" ;;
        7) printf '%s' "$(get_text watchdog.invalid-memory-access)" ;;
        9) printf '%s' "$(get_text watchdog.forced-stop)" ;;
        11) printf '%s' "$(get_text watchdog.internal-program-error)" ;;
        13) printf '%s' "$(get_text watchdog.interrupted-write)" ;;
        15) printf '%s' "$(get_text watchdog.stop-request)" ;;
        *) printf '%s' "$(get_text watchdog.signal "$1")" ;;
    esac
}

get_crash_sentence() {
    local label="$1"
    local status="$2"
    local signal phrase journal
    if [[ "${status}" -ge 128 ]]; then
        signal=$((status - 128))
        phrase="$(signal_phrase "${signal}")"
        printf "$(get_text watchdog.the-check-crashed-signal-it-did-not-finish "${label}" "${signal}" "${phrase}")"
    else
        printf "$(get_text watchdog.the-check-stopped-code-it-did-not-finish "${label}" "${status}")"
    fi
    journal="${LOG_FILE:-${LOG:-}}"
    if [[ -n "${journal}" ]]; then
        printf "$(get_text watchdog.the-journal-is "${journal}")"
    fi
    printf "$(get_text log.n)"
}

send_crash_mail() {
    local status=$?
    if [[ -n "${1-}" ]]; then
        status="$1"
    fi
    trap - EXIT
    [[ "${status}" -eq 0 ]] && return 0
    log_alert "$(get_crash_sentence "${CRASH_LABEL:-contrôle}" "${status}")" || true
}

arm_crash_mail() {
    CRASH_LABEL="$1"
    trap send_crash_mail EXIT
}
