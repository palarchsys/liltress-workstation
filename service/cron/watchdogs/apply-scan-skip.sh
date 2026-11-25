#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/apply-scan-skip.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Apply the on-access excludes to the scanner configuration.
# Note       : Fixed excludes from onaccess.conf join the same block.
# Note       : The temporary file is created under the product run directory.
# Note       : Each OnAccessExcludePath value matches that directory only.
# -----------------------------------------------------------------------------


# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../../core/boot/python.sh"
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

# Placeholders expand and the product source tree stays out.
apply_onaccess_placeholder() {
    local path
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
    apply_onaccess_placeholder
}

read_generated_clamav() {
    local file="${BASE}/config/service/exclusions/generated/clamav-skip.paths"
    local line
    [[ -f "${file}" ]] || return 0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        case "${line}" in
            "" | \#*) continue ;;
        esac
        SCAN_SKIP_VALID+=("${line}")
    done <"${file}"
}

read_scan_run_directory() {
    local candidate="" line=""
    for candidate in \
        "${BASE}/config/service/clamav/scan.conf" \
        "${CONFIG_BASE_DIRECTORY:-}/config/service/clamav/scan.conf" \
        "${INSTALL_DIRECTORY:-}/config/service/clamav/scan.conf"; do
        [[ -n "${candidate}" && -f "${candidate}" ]] || continue
        while IFS= read -r line || [[ -n "${line}" ]]; do
            case "${line}" in
                run-directory=*)
                    printf '%s\n' "${line#run-directory=}"
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
read_generated_clamav
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
    run_directory="$(read_scan_run_directory)"
    install -d -m 755 "${run_directory}"
    tmp="$(mktemp -p "${run_directory}")"
    trap 'rm -f "${tmp}"' EXIT
    changed="$(
        python3 "$(locate_python_directory)/scan-skip-apply.py" "${conf}" "${tmp}" "${#ONACCESS_FIXED[@]}" "${ONACCESS_FIXED[@]}" "${SCAN_SKIP_VALID[@]}"
    )"
    if [[ "${changed}" == "changed" ]]; then
        cat "${tmp}" >"${conf}"
        restart_scan_skip_service
    fi
    rm -f "${tmp}"
    trap - EXIT
fi
exit 0
