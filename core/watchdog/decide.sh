#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/decide.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Classify one watchdog phase as clean, false positive, or real.
# Note       : A hold class stays real unless the path was repaired or is listed in an exclude file.
# Note       : An added product timer link under timers.target.wants is explained.
# -----------------------------------------------------------------------------


show_exclusion_alert() {
    local seen="$1"
    local extra="${BASE:-}/config/service/exclusions/generated/alert-exclude.list"
    local line
    [[ -n "${BASE:-}" && -f "${extra}" && "${extra}" != "${seen}" ]] || return 0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        case "${line}" in
            "" | \#*) continue ;;
            *)
                printf '%s\n' "${extra}"
                return 0
                ;;
        esac
    done <"${extra}"
}

read_watchdog_exclude() {
    local here shared product seen=""
    here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    shared=""
    for shared in \
        "${here}/../../config/service/alert/exclude.list" \
        "${BASE:-}/config/service/alert/exclude.list" \
        "${CONFIG_BASE_DIRECTORY:-}/config/service/alert/exclude.list"; do
        [[ -f "${shared}" ]] && break
        shared=""
    done
    if [[ -f "${shared}" ]]; then
        printf '%s\n' "${shared}"
        seen="${shared}"
    fi
    if declare -F locate_config_file >/dev/null 2>&1; then
        product="$(locate_config_file service/alert/exclude.list 2>/dev/null || true)"
        if [[ -n "${product}" && "${product}" != "${seen}" && -f "${product}" ]]; then
            printf '%s\n' "${product}"
        fi
    fi
    show_exclusion_alert "${seen}"
}

# Return 0 when a malware journal belongs to this phase.
pass_malware_log() {
    case "$1" in
        clamav-* | chkrootkit-* | rkhunter-* | crash-clamav* | crash-chkrootkit* | crash-rkhunter*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Return 0 when an integrity journal belongs to this phase.
pass_integrity_log() {
    case "$1" in
        debsums-* | auditd-* | aide-* | rkhunter-* | chkrootkit-* | crash-debsums* | crash-auditd* | crash-aide* | crash-rkhunter* | crash-chkrootkit*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Return 0 when an evergreen journal belongs to this phase.
pass_evergreen_log() {
    case "$1" in
        clamav-* | crowdsec-* | fail2ban-* | crash-clamav* | crash-crowdsec* | crash-fail2ban*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Return 0 when this journal belongs to the phase.
pass_watchdog_log() {
    local name="$1"
    local phase="$2"
    case "${name}" in
        alert-*.zip | watchdog-chain.lock | watchdog-chain.stamp) return 1 ;;
    esac
    case "${phase}" in
        malware) pass_malware_log "${name}" ;;
        integrity) pass_integrity_log "${name}" ;;
        evergreen) pass_evergreen_log "${name}" ;;
        *) return 0 ;;
    esac
}

collect_watchdog_logs() {
    local source_dir="$1"
    local dest_dir="$2"
    local since="$3"
    local phase="${4:-}"
    local path="" name=""
    mkdir -p "${dest_dir}"
    [[ -d "${source_dir}" ]] || return 0
    while IFS= read -r path; do
        [[ -n "${path}" && -f "${path}" ]] || continue
        name="$(basename -- "${path}")"
        pass_watchdog_log "${name}" "${phase}" || continue
        cp -f -- "${path}" "${dest_dir}/${name}" 2>/dev/null || true
    done < <(find "${source_dir}" -maxdepth 1 -type f -newermt "@${since}" -print 2>/dev/null || true)
}

check_watchdog_phase() {
    local phase="$1"
    local log_dir="$2"
    local since="$3"
    local repair_file="$4"
    local state_dir="$5"
    local catalog here excludes="" apt_history dpkg_log
    here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    catalog="${here}/alert-advice.txt"
    apt_history="${6:-/var/log/apt/history.log}"
    dpkg_log="${7:-/var/log/dpkg.log}"
    mkdir -p "${state_dir}"
    excludes="$(read_watchdog_exclude | awk 'NR > 1 { printf ":" } { printf "%s", $0 }')"
    action_json="${here}/../../config/service/alert/action.json"
    WATCHDOG_STATUS="$(
        WATCHDOG_EXCLUDES="${excludes}" \
            python3 "${here}/../../python/alert-decide.py" "${phase}" "${log_dir}" "${since}" "${repair_file}" "${catalog}" "${apt_history}" "${dpkg_log}" "${state_dir}" "${action_json}"
    )" || WATCHDOG_STATUS="real"
    export WATCHDOG_STATUS
    printf '%s\n' "${WATCHDOG_STATUS}"
}
