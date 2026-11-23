#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/apply-scan-skip.sh
# Updated at : 2026-11-23
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Apply the on-access excludes to the scanner configuration.
# Note       : Fixed excludes from onaccess.conf join the same block.
# Note       : The temporary file is created under the product run directory.
# Note       : Each OnAccessExcludePath value matches that directory only.
# -----------------------------------------------------------------------------


# The caller owns shown_python and reads it after this call.
show_python_directory() {
    local candidate="$1"
    shown_python=0
    [[ -n "${candidate}" && -d "${candidate}" ]] || return 0
    (cd -- "${candidate}" && pwd -P)
    shown_python=1
    return 0
}

# The shared directory is printed as given, without resolving links.
show_share_python() {
    local dir="$1"
    shown_python=0
    if [[ ! -d "${dir}/share/python" ]]; then
        return 0
    fi
    printf '%s\n' "${dir}/share/python"
    shown_python=1
    return 0
}

locate_python_dir() {
    local dir="" hops=0 candidate="" shown_python=0
    for candidate in \
        "${CONFIG_BASE_DIRECTORY:-}/python" \
        "${BASE:-}/python" \
        "${INSTALL_DIRECTORY:-}/python" \
        "${INSTALL_DIRECTORY:-}/../share/python"; do
        show_python_directory "${candidate}"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
    done
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        show_share_python "${dir}"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
        show_python_directory "${dir}/python"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/scan-skip-lib.sh"

restart_scan_skip_service() {
    local unit
    if systemctl cat clamav-daemon.service >/dev/null 2>&1; then
        systemctl restart clamav-daemon
    fi
    for unit in clamav-clamonacc.service clamonacc.service; do
        if systemctl cat "${unit}" >/dev/null 2>&1; then
            systemctl restart "${unit}"
            return 0
        fi
    done
}

load_onaccess_exclude() {
    local candidate found=""
    ONACCESS_FIXED_EXCLUDE="${ONACCESS_FIXED_EXCLUDE:-/var/lib/snapd /snap /var/lib/clamav/quarantine /var/lib/clamav/tmp /var/log}"
    for candidate in \
        "${INSTALL_DIRECTORY:-}/config/service/clamav/onaccess.conf" \
        "${BASE}/config/service/clamav/onaccess.conf" \
        "/opt/liltress-workstation/config/service/clamav/onaccess.conf"; do
        [[ -f "${candidate}" ]] || continue
        found="${candidate}"
        break
    done
    if [[ -n "${found}" ]]; then
        # shellcheck disable=SC1090
        source "${found}"
    fi
    ONACCESS_FIXED=()
    local path
    # shellcheck disable=SC2086
    for path in ${ONACCESS_FIXED_EXCLUDE}; do
        [[ -n "${path}" ]] || continue
        ONACCESS_FIXED+=("${path}")
    done
    local kept=()
    local rendered=""
    for path in "${ONACCESS_FIXED[@]+"${ONACCESS_FIXED[@]}"}"; do
        rendered="${path//__HF_BASE__/${BASE}}"
        rendered="${rendered//__BASE__/${BASE}}"
        [[ "${rendered}" == "${BASE}/src" ]] && continue
        kept+=("${rendered}")
    done
    ONACCESS_FIXED=("${kept[@]+"${kept[@]}"}")
}

read_scan_run_dir() {
    local candidate="" line=""
    for candidate in \
        "${BASE}/config/service/clamav/scan.conf" \
        "${CONFIG_BASE_DIRECTORY:-}/config/service/clamav/scan.conf" \
        "${INSTALL_DIRECTORY:-}/config/service/clamav/scan.conf"; do
        [[ -n "${candidate}" && -f "${candidate}" ]] || continue
        while IFS= read -r line || [[ -n "${line}" ]]; do
            case "${line}" in
                run-dir=*)
                    printf '%s\n' "${line#run-dir=}"
                    return 0
                    ;;
            esac
        done <"${candidate}"
    done
    printf '%s\n' "/run/liltress-workstation"
}

if [[ -n "${SCAN_SKIP_HOME:-}" ]]; then
    ensure_scan_skip_file "${SCAN_SKIP_HOME}"
fi

load_onaccess_exclude
collect_scan_skip_path
if [[ ${#SCAN_SKIP_BAD[@]} -gt 0 ]]; then
    if ! declare -F get_text >/dev/null 2>&1; then
        # shellcheck disable=SC1090
        source "${HERE}/text-load.sh"
    fi
    install -d -m 750 "${BASE}/cron/security_logs"
    for line in "${SCAN_SKIP_BAD[@]}"; do
        printf "$(get_text watchdog.s-path-denied-s-n)" "$(date -Iseconds)" "${line}" | tee -a "${BASE}/cron/security_logs/scan-skip.log"
    done
fi

conf="/etc/clamav/clamd.conf"
if [[ -f "${conf}" ]]; then
    run_dir="$(read_scan_run_dir)"
    install -d -m 755 "${run_dir}"
    tmp="$(mktemp -p "${run_dir}")"
    trap 'rm -f "${tmp}"' EXIT
    changed="$(
        python3 "$(locate_python_dir)/scan-skip-apply.py" "${conf}" "${tmp}" "${#ONACCESS_FIXED[@]}" "${ONACCESS_FIXED[@]}" "${SCAN_SKIP_VALID[@]}"
    )"
    if [[ "${changed}" == "changed" ]]; then
        cat "${tmp}" >"${conf}"
        restart_scan_skip_service
    fi
    rm -f "${tmp}"
    trap - EXIT
fi
exit 0
