#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/remedy.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Quarantine a real finding and reinstall the package that owns it.
# Note       : A baseline is refreshed only after the repair of that tool succeeded.
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

watchdog_case_actions() {
    local tool="$1"
    local class_id="$2"
    local branch="$3"
    local catalog=""
    catalog="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../config/service/alert/action.json"
    [[ -f "${catalog}" ]] || return 0
    python3 "$(locate_python_dir)/alert-remedy.py" "${catalog}" "${tool}" "${class_id}" "${branch}"
}

watchdog_case_has() {
    local tool="$1"
    local class_id="$2"
    local branch="$3"
    local action="$4"
    local found=""
    found="$(watchdog_case_actions "${tool}" "${class_id}" "${branch}")"
    [[ -z "${found}" ]] && return 0
    grep -qx "${action}" <<<"${found}"
}

reinstall_watchdog_package() {
    local package="$1"
    local status=0
    [[ -n "${package}" && "${package}" != "-" ]] || return 1
    command -v apt-get >/dev/null 2>&1 || return 1
    DEBIAN_FRONTEND=noninteractive \
        NEEDRESTART_MODE=l \
        APT_LISTCHANGES_FRONTEND=none \
        apt-get install --reinstall -y -o Dpkg::Options::=--force-confold -- "${package}" >/dev/null 2>&1 || status=$?
    return "${status}"
}

refresh_watchdog_baseline() {
    local tool="$1"
    local base=""
    base="$(get_product_base)"
    case "${tool}" in
        aide)
            if [[ -x "${base}/service/aide/refresh-db.sh" ]]; then
                run_limited bash "${base}/service/aide/refresh-db.sh"
            elif command -v aide >/dev/null 2>&1; then
                run_limited aide --update
            else
                return 1
            fi
            ;;
        rkhunter)
            if [[ -x "${base}/service/rkhunter/refresh-db.sh" ]]; then
                run_limited bash "${base}/service/rkhunter/refresh-db.sh"
            elif command -v rkhunter >/dev/null 2>&1; then
                run_limited rkhunter --propupd --nocolors
            else
                return 1
            fi
            ;;
        chkrootkit)
            if [[ -x "${base}/service/chkrootkit/ignore-log.sh" && -n "${WATCHDOG_LOG:-}" ]]; then
                run_limited bash "${base}/service/chkrootkit/ignore-log.sh" "${WATCHDOG_LOG}"
            else
                return 1
            fi
            ;;
        *)
            return 0
            ;;
    esac
}

# A malware path is moved aside when the class allows it and the path is safe.
apply_watchdog_quarantine() {
    local phase="$1"
    local state_dir="$2"
    local moment="$3"
    local deny="$4"
    local path="$5"
    local tool="$6"
    local class_id="$7"
    local action="" stored=""
    if [[ "${phase}" != "integrity" && "${path}" != "-" && "${deny}" != *"|${path}|"* ]] \
        && watchdog_case_has "${tool}" "${class_id}" real quarantine; then
        if declare -F take_quarantine_file >/dev/null 2>&1; then
            take_quarantine_file "${path}" || true
            stored="${MOVE_STORED:-${path}}"
            action="$(get_text alert.mail.action.quarantine "${stored}")"
            printf '%s - %s\n' "${moment}" "${action}" >>"${state_dir}/actions.txt"
        fi
    fi
}

# A package row is installed again. Other kinds stay unchanged.
apply_watchdog_reinstall() {
    local phase="$1"
    local state_dir="$2"
    local moment="$3"
    local kind="$4"
    local name="$5"
    local path="$6"
    local action="" package=""
    if [[ "${kind}" == "package" && -n "${name}" && "${name}" != "-" ]]; then
        package="${name}"
    fi
    if [[ -z "${package}" ]]; then
        return 0
    fi
    if reinstall_watchdog_package "${package}"; then
        if [[ "${phase}" == "integrity" ]]; then
            action="$(get_text alert.mail.action.debsums "${package}")"
        else
            action="$(get_text alert.mail.action.reinstall "${package}")"
        fi
        printf '%s - %s\n' "${moment}" "${action}" >>"${state_dir}/actions.txt"
        if [[ "${path}" != "-" ]]; then
            printf '%s\n' "${path}" >>"${state_dir}/repaired.txt"
        fi
        return 0
    fi
    action="$(get_text alert.mail.action.failed "${package}")"
    printf '%s - %s\n' "${moment}" "${action}" >>"${state_dir}/actions.txt"
}

# A real row is quarantined or installed again. An explained row is ignored.
apply_watchdog_row() {
    local phase="$1"
    local state_dir="$2"
    local moment="$3"
    local deny="$4"
    local explained="$5"
    local hold="$6"
    local kind="$7"
    local name="$8"
    local when="$9"
    local path="${10}"
    local tool="${11}"
    local class_id="${12}"
    local action=""
    [[ -n "${explained}" ]] || return 0
    [[ "${explained}" == "0" ]] || return 0
    if [[ "${class_id}" == "debsums.repair" ]]; then
        action="$(get_text alert.mail.action.debsums "${name}")"
        printf '%s - %s\n' "${moment}" "${action}" >>"${state_dir}/actions.txt"
        printf '%s\n' "${name}" >>"${state_dir}/repaired.txt"
        return 0
    fi
    if [[ "${kind}" == "jail" || "${kind}" == "scenario" ]]; then
        action="$(get_text alert.mail.action.ban "${name}")"
        printf '%s - %s\n' "${moment}" "${action}" >>"${state_dir}/actions.txt"
        return 0
    fi
    if [[ "${class_id}" == "crash" ]]; then
        action="$(get_text alert.mail.action.crash "${tool}")"
        printf '%s - %s\n' "${moment}" "${action}" >>"${state_dir}/actions.txt"
        return 0
    fi
    apply_watchdog_quarantine "${phase}" "${state_dir}" "${moment}" "${deny}" "${path}" "${tool}" "${class_id}"
    apply_watchdog_reinstall "${phase}" "${state_dir}" "${moment}" "${kind}" "${name}" "${path}"
}

apply_watchdog_remedy() {
    local phase="$1"
    local state_dir="$2"
    local moment=""
    local explained="" hold="" kind="" name="" when="" path="" tool="" class_id=""
    local deny="|/etc/passwd|/etc/shadow|/etc/sudoers|/etc/ssh/sshd_config|/usr/bin/sudo|/usr/bin/passwd|/usr/sbin/sshd|"
    : >"${state_dir}/actions.txt"
    : >"${state_dir}/repaired.txt"
    [[ -f "${state_dir}/rows.tsv" ]] || return 0
    moment="$(date '+%Y-%m-%d %H:%M:%S')"
    while IFS=$'\t' read -r explained hold kind name when path tool class_id; do
        apply_watchdog_row "${phase}" "${state_dir}" "${moment}" "${deny}" \
            "${explained}" "${hold}" "${kind}" "${name}" \
            "${when}" "${path}" "${tool}" "${class_id}"
    done <"${state_dir}/rows.tsv"
}

# The caller owns repaired. Each repaired path is stored between bars.
collect_repaired_paths() {
    local path=""
    repaired="|"
    [[ -f "${state_dir}/repaired.txt" ]] || return 0
    while IFS= read -r path; do
        [[ -n "${path}" ]] || continue
        repaired="${repaired}${path}|"
    done <"${state_dir}/repaired.txt"
}

# The caller owns blocked and real_count. A crash or an open path blocks that tool.
collect_blocked_tools() {
    local row_explained="" row_hold="" row_kind="" row_name="" row_when=""
    local path="" tool="" class_id=""
    blocked="|"
    real_count=0
    while IFS=$'\t' read -r row_explained row_hold row_kind row_name row_when path tool class_id; do
        [[ "${row_explained}" == "0" ]] || continue
        real_count=$((real_count + 1))
        if [[ "${class_id}" == "crash" ]]; then
            blocked="${blocked}${tool}|"
        fi
        if [[ "${path}" != "-" && "${repaired}" != *"|${path}|"* && "${row_kind}" != "jail" && "${row_kind}" != "scenario" ]]; then
            blocked="${blocked}${tool}|"
        fi
    done <"${state_dir}/rows.tsv"
}

# The caller owns seen. A tool that is still blocked keeps its current baseline.
refresh_open_baselines() {
    local row_explained="" row_hold="" row_kind="" row_name="" row_when=""
    local path="" tool="" class_id="" action=""
    while IFS=$'\t' read -r row_explained row_hold row_kind row_name row_when path tool class_id; do
        [[ -n "${tool}" ]] || continue
        [[ "${seen}" == *"|${tool}|"* ]] && continue
        if [[ "${real_count}" -gt 0 && "${blocked}" == *"|${tool}|"* ]]; then
            continue
        fi
        seen="${seen}${tool}|"
        refresh_watchdog_baseline "${tool}" || continue
        action="$(get_text alert.mail.action.baseline "${tool}")"
        printf '%s - %s\n' "${moment}" "${action}" >>"${state_dir}/actions.txt"
    done <"${state_dir}/rows.tsv"
}

refresh_watchdog_rows() {
    local state_dir="$1"
    local moment=""
    local repaired="|" blocked="|" seen="|" real_count=0
    moment="$(date '+%Y-%m-%d %H:%M:%S')"
    [[ -f "${state_dir}/rows.tsv" ]] || return 0
    collect_repaired_paths
    collect_blocked_tools
    refresh_open_baselines
}
