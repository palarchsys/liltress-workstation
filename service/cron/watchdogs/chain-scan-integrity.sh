#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/chain-scan-integrity.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Run the integrity tools, then one mail when a case is real.
# Note       : One failure leaves the next tool free to run.
# Note       : A clean pass sends no mail.
# -----------------------------------------------------------------------------


run_integrity_tool() {
    local tool="$1"
    local status_file="$2"
    local bin="${HERE}/scan-${tool}.sh"
    local status=0
    if [[ ! -x "${bin}" ]]; then
        printf '%s\n' 0 >"${status_file}"
        return 0
    fi
    set +e
    WATCHDOG_HOLD_MAIL=1 run_limited bash "${bin}"
    status=$?
    set -e
    printf '%s\n' "${status}" >"${status_file}"
}

run_integrity_tools() {
    local state_directory="$1"
    local log_copy="$2"
    local tool="" status=""
    local tools=(auditd rkhunter chkrootkit debsums aide)
    for tool in "${tools[@]}"; do
        run_integrity_tool "${tool}" "${state_directory}/exit-${tool}"
        status="$(tr -d '[:space:]' <"${state_directory}/exit-${tool}")"
        if [[ "${status}" -ge 128 ]]; then
            printf '%s\n' "${tool} ${status}" >"${log_copy}/crash-${tool}.log"
        fi
    done
}

finish_integrity_phase() {
    local state_directory="$1"
    local status="" zip_path=""
    status="$(tr -d '[:space:]' <"${state_directory}/status" 2>/dev/null || true)"
    case "${status}" in
        clean | "")
            return 0
            ;;
        false)
            refresh_watchdog_rows "${state_directory}" || true
            ;;
        real)
            apply_watchdog_remedy integrity "${state_directory}"
            refresh_watchdog_rows "${state_directory}" || true
            render_watchdog_rows "${state_directory}"
            zip_path="$(write_watchdog_pack integrity "${state_directory}" "${state_directory}/logs")"
            send_watchdog_report integrity "${state_directory}" "${zip_path}"
            ;;
    esac
}

run_integrity_chain() {
    local base="" since="" previous="" state_directory="" log_source="" log_copy="" phase_start=""
    base="$(get_product_base)"
    previous="$(get_watchdog_runtime_file "${base}" watchdog-chain.stamp)"
    if [[ -f "${previous}" ]]; then
        since="$(tr -d '[:space:]' <"${previous}")"
    else
        since="$(($(date +%s) - 86400))"
    fi
    state_directory="$(mktemp -d)"
    log_source="${base}/cron/security_logs"
    log_copy="${state_directory}/logs"
    mkdir -p -- "${log_copy}" "${log_source}"
    phase_start="$(date +%s)"
    run_integrity_tools "${state_directory}" "${log_copy}"
    collect_watchdog_logs "${log_source}" "${log_copy}" "${phase_start}" integrity
    check_watchdog_phase integrity "${log_copy}" "${since}" "${state_directory}/repair.txt" "${state_directory}" >/dev/null
    finish_integrity_phase "${state_directory}"
    rm -rf -- "${state_directory}"
}

set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/common.sh"
if [[ -f "${BASE}/cron/mail.conf" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${BASE}/cron/mail.conf"
    set +a
fi
run_integrity_chain
exit 0
