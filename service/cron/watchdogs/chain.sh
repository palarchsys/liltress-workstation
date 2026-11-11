#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/chain.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

# -----------------------------------------------------------------------------
# Purpose    : Run the malware watchdogs, then the integrity watchdogs.
# Note       : A second start exits while the flock is held.
# Note       : Each tool stays under the existing CPU and IO limits.
# -----------------------------------------------------------------------------

set -euo pipefail

chain_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
for chain_candidate in \
    "${chain_dir}/../../../core/watchdog/load.sh" \
    "${chain_dir}/../../../../share/core/watchdog/load.sh"
do
    if [[ -f "${chain_candidate}" ]]; then
        # shellcheck disable=SC1090
        source "${chain_candidate}"
        break
    fi
done
load_shared_watchdog "${chain_dir}"

run_watchdog_tool() {
    local tool="$1"
    local base="$2"
    local status_file="$3"
    local bin="${base}/cron/bin/${tool}.sh"
    local status=0
    if [[ ! -x "${bin}" ]]; then
        printf '%s\n' 0 > "${status_file}"
        return 0
    fi
    set +e
    WATCHDOG_HOLD_MAIL=1 run_limited bash "${bin}"
    status=$?
    set -e
    printf '%s\n' "${status}" > "${status_file}"
}

run_watchdog_phase() {
    local phase="$1"
    local base="$2"
    local since="$3"
    local repair_file="$4"
    local state_dir="$5"
    local log_source="${base}/cron/security_logs"
    local log_copy="${state_dir}/logs"
    local tool status tools=()
    case "${phase}" in
        malware) tools=(clamav chkrootkit rkhunter) ;;
        integrity) tools=(debsums auditd aide) ;;
        *) return 0 ;;
    esac
    mkdir -p -- "${log_copy}" "${log_source}"
    for tool in "${tools[@]}"; do
        run_watchdog_tool "${tool}" "${base}" "${state_dir}/exit-${tool}"
        status="$(tr -d '[:space:]' < "${state_dir}/exit-${tool}")"
        if [[ "${status}" -ge 128 ]]; then
            printf '%s\n' "${tool} ${status}" > "${log_copy}/crash-${tool}.log"
        fi
    done
    collect_watchdog_logs "${log_source}" "${log_copy}" "${since}"
    check_watchdog_phase "${phase}" "${log_copy}" "${since}" "${repair_file}" "${state_dir}" >/dev/null
}

finish_watchdog_phase() {
    local phase="$1"
    local state_dir="$2"
    local status zip_path=""
    status="$(tr -d '[:space:]' < "${state_dir}/status" 2>/dev/null || true)"
    case "${status}" in
        clean|"")
            return 0
            ;;
        false)
            refresh_watchdog_rows "${state_dir}" || true
            ;;
        real)
            apply_watchdog_remedy "${phase}" "${state_dir}"
            refresh_watchdog_rows "${state_dir}" || true
            render_watchdog_rows "${state_dir}"
            zip_path="$(write_watchdog_pack "${phase}" "${state_dir}" "${state_dir}/logs")"
            send_watchdog_report "${phase}" "${state_dir}" "${zip_path}"
            if [[ -s "${state_dir}/repaired.txt" ]]; then
                cp -f -- "${state_dir}/repaired.txt" "${state_dir}/../repair.txt"
            fi
            ;;
    esac
}

run_watchdog_chain() {
    local base lock_path since previous state_root malware_dir integrity_dir repair_file
    base="$(get_product_base)"
    mkdir -p -- "${base}/cron" "${base}/log"
    lock_path="${base}/cron/watchdog-chain.lock"
    exec 9>"${lock_path}"
    if ! flock -n 9; then
        return 0
    fi
    previous="${base}/cron/watchdog-chain.stamp"
    if [[ -f "${previous}" ]]; then
        since="$(tr -d '[:space:]' < "${previous}")"
    else
        since="$(( $(date +%s) - 86400 ))"
    fi
    state_root="$(mktemp -d)"
    malware_dir="${state_root}/malware"
    integrity_dir="${state_root}/integrity"
    repair_file="${state_root}/repair.txt"
    : > "${repair_file}"
    mkdir -p -- "${malware_dir}" "${integrity_dir}"
    run_watchdog_phase malware "${base}" "${since}" "${repair_file}" "${malware_dir}"
    finish_watchdog_phase malware "${malware_dir}"
    run_watchdog_phase integrity "${base}" "${since}" "${repair_file}" "${integrity_dir}"
    finish_watchdog_phase integrity "${integrity_dir}"
    date +%s > "${previous}"
    chmod 600 "${previous}" 2>/dev/null || true
    rm -rf -- "${state_root}"
}

run_watchdog_chain
