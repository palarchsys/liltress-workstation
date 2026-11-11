#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/remedy.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

# -----------------------------------------------------------------------------
# Purpose    : Quarantine a real finding and reinstall the package that owns it.
# Note       : A baseline is refreshed only after the repair of that tool succeeded.
# -----------------------------------------------------------------------------

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
            if [[ -x "${base}/bin/aide-refresh-db.sh" ]]; then
                run_limited bash "${base}/bin/aide-refresh-db.sh"
            elif command -v aide >/dev/null 2>&1; then
                run_limited aide --update
            else
                return 1
            fi
            ;;
        rkhunter)
            if [[ -x "${base}/bin/rkhunter-refresh-db.sh" ]]; then
                run_limited bash "${base}/bin/rkhunter-refresh-db.sh"
            elif command -v rkhunter >/dev/null 2>&1; then
                run_limited rkhunter --propupd --nocolors
            else
                return 1
            fi
            ;;
        chkrootkit)
            if [[ -x "${base}/bin/chkrootkit-ignore-log.sh" && -n "${WATCHDOG_LOG:-}" ]]; then
                run_limited bash "${base}/bin/chkrootkit-ignore-log.sh" "${WATCHDOG_LOG}"
            else
                return 1
            fi
            ;;
        *)
            return 0
            ;;
    esac
}

apply_watchdog_remedy() {
    local phase="$1"
    local state_dir="$2"
    local row explained hold kind name when path tool class_id
    local moment action package stored
    local deny="|/etc/passwd|/etc/shadow|/etc/sudoers|/etc/ssh/sshd_config|/usr/bin/sudo|/usr/bin/passwd|/usr/sbin/sshd|"
    : > "${state_dir}/actions.txt"
    : > "${state_dir}/repaired.txt"
    [[ -f "${state_dir}/rows.tsv" ]] || return 0
    moment="$(date '+%Y-%m-%d %H:%M:%S')"
    while IFS=$'\t' read -r explained hold kind name when path tool class_id; do
        [[ -n "${explained}" ]] || continue
        [[ "${explained}" == "0" ]] || continue
        if [[ "${class_id}" == "debsums.repair" ]]; then
            action="$(get_text alert.mail.action.debsums "${name}")"
            printf '%s - %s\n' "${moment}" "${action}" >> "${state_dir}/actions.txt"
            printf '%s\n' "${name}" >> "${state_dir}/repaired.txt"
            continue
        fi
        if [[ "${kind}" == "jail" || "${kind}" == "scenario" ]]; then
            action="$(get_text alert.mail.action.ban "${name}")"
            printf '%s - %s\n' "${moment}" "${action}" >> "${state_dir}/actions.txt"
            continue
        fi
        if [[ "${class_id}" == "crash" ]]; then
            action="$(get_text alert.mail.action.crash "${tool}")"
            printf '%s - %s\n' "${moment}" "${action}" >> "${state_dir}/actions.txt"
            continue
        fi
        if [[ "${phase}" != "integrity" && "${path}" != "-" && "${deny}" != *"|${path}|"* ]]; then
            if declare -F take_quarantine_file >/dev/null 2>&1; then
                take_quarantine_file "${path}" || true
                stored="${MOVE_STORED:-${path}}"
                action="$(get_text alert.mail.action.quarantine "${stored}")"
                printf '%s - %s\n' "${moment}" "${action}" >> "${state_dir}/actions.txt"
            fi
        fi
        package="${name}"
        if [[ "${kind}" != "package" ]]; then
            package=""
        fi
        if reinstall_watchdog_package "${package}"; then
            if [[ "${phase}" == "integrity" ]]; then
                action="$(get_text alert.mail.action.debsums "${package}")"
            else
                action="$(get_text alert.mail.action.reinstall "${package}")"
            fi
            printf '%s - %s\n' "${moment}" "${action}" >> "${state_dir}/actions.txt"
            if [[ "${path}" != "-" ]]; then
                printf '%s\n' "${path}" >> "${state_dir}/repaired.txt"
            fi
        else
            action="$(get_text alert.mail.action.failed "${name}")"
            printf '%s - %s\n' "${moment}" "${action}" >> "${state_dir}/actions.txt"
        fi
    done < "${state_dir}/rows.tsv"
}

refresh_watchdog_rows() {
    local state_dir="$1"
    local moment tool path class_id row_explained row_hold row_kind row_name row_when
    local repaired="|" blocked="|" seen="|" real_count=0 action
    moment="$(date '+%Y-%m-%d %H:%M:%S')"
    [[ -f "${state_dir}/rows.tsv" ]] || return 0
    if [[ -f "${state_dir}/repaired.txt" ]]; then
        while IFS= read -r path; do
            [[ -n "${path}" ]] || continue
            repaired="${repaired}${path}|"
        done < "${state_dir}/repaired.txt"
    fi
    while IFS=$'\t' read -r row_explained row_hold row_kind row_name row_when path tool class_id; do
        [[ "${row_explained}" == "0" ]] || continue
        real_count=$((real_count + 1))
        if [[ "${class_id}" == "crash" ]]; then
            blocked="${blocked}${tool}|"
        fi
        if [[ "${path}" != "-" && "${repaired}" != *"|${path}|"* && "${row_kind}" != "jail" && "${row_kind}" != "scenario" ]]; then
            blocked="${blocked}${tool}|"
        fi
    done < "${state_dir}/rows.tsv"
    while IFS=$'\t' read -r row_explained row_hold row_kind row_name row_when path tool class_id; do
        [[ -n "${tool}" ]] || continue
        [[ "${seen}" == *"|${tool}|"* ]] && continue
        if [[ "${real_count}" -gt 0 && "${blocked}" == *"|${tool}|"* ]]; then
            continue
        fi
        seen="${seen}${tool}|"
        refresh_watchdog_baseline "${tool}" || continue
        action="$(get_text alert.mail.action.baseline "${tool}")"
        printf '%s - %s\n' "${moment}" "${action}" >> "${state_dir}/actions.txt"
    done < "${state_dir}/rows.tsv"
}
