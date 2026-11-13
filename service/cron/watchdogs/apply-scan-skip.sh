#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/apply-scan-skip.sh
# Updated at : 2026-11-06
# Creator    : palarchsys
# =============================================================================

locate_python_dir() {
    local dir hops=0 candidate
    for candidate in \
        "${CONFIG_BASE_DIRECTORY:-}/python" \
        "${BASE:-}/python" \
        "${INSTALL_DIRECTORY:-}/python" \
        "${INSTALL_DIRECTORY:-}/../share/python"
    do
        if [[ -n "${candidate}" && -d "${candidate}" ]]; then
            (cd -- "${candidate}" && pwd -P)
            return 0
        fi
    done
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        if [[ -d "${dir}/share/python" ]]; then
            printf '%s\n' "${dir}/share/python"
            return 0
        fi
        if [[ -d "${dir}/python" ]]; then
            (cd -- "${dir}/python" && pwd -P)
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

# -----------------------------------------------------------------------------
# Note       : Fixed excludes from onaccess.conf join the same block.
# Note       : The temporary file is created under /run/liltress-workstation.
# Note       : Each OnAccessExcludePath value matches that directory only.
# -----------------------------------------------------------------------------

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

if [[ -n "${SCAN_SKIP_HOME:-}" ]]; then
    ensure_scan_skip_file "${SCAN_SKIP_HOME}"
fi

load_onaccess_exclude() {
    local candidate found=""
    ONACCESS_FIXED_EXCLUDE="${ONACCESS_FIXED_EXCLUDE:-/var/lib/snapd /snap /var/lib/clamav/quarantine /var/lib/clamav/tmp /var/log}"
    for candidate in \
        "${INSTALL_DIRECTORY:-}/config/clamav/onaccess.conf" \
        "${BASE}/config/clamav/onaccess.conf" \
        "/opt/liltress-workstation/config/clamav/onaccess.conf"
    do
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
    for path in "${ONACCESS_FIXED[@]+"${ONACCESS_FIXED[@]}"}"; do
        [[ "${path}" == "${BASE}/src" ]] && continue
        kept+=("${path}")
    done
    ONACCESS_FIXED=("${kept[@]+"${kept[@]}"}")
}

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
    install -d -m 755 /run/liltress-workstation
    tmp="$(mktemp -p /run/liltress-workstation)"
    trap 'rm -f "${tmp}"' EXIT
    changed="$(python3 "$(locate_python_dir)/scan-skip-apply.py" "${conf}" "${tmp}" "${#ONACCESS_FIXED[@]}" "${ONACCESS_FIXED[@]}" "${SCAN_SKIP_VALID[@]}"
)"
    if [[ "${changed}" == "changed" ]]; then
        cat "${tmp}" > "${conf}"
        restart_scan_skip_service
    fi
    rm -f "${tmp}"
    trap - EXIT
fi

rk="/etc/rkhunter.conf.local"
if [[ -f "${rk}" && ${#SCAN_SKIP_VALID[@]} -gt 0 ]]; then
    for path in "${SCAN_SKIP_VALID[@]}"; do
        case "${path}" in
            */.*)
                grep -qxF "ALLOWHIDDENDIR=${path}" "${rk}" \
                    || printf 'ALLOWHIDDENDIR=%s\n' "${path}" >> "${rk}"
                ;;
        esac
    done
fi
exit 0
