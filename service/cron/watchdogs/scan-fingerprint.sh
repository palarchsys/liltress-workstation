#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/scan-fingerprint.sh
# Updated at : 2026-11-21
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Compare file digests with the saved stamp and alert when they differ.
# Note       : The stamp lives under the product cron directory.
# Note       : The opening visit stores the stamp and stays silent.
# -----------------------------------------------------------------------------


read_scan_run_dir() {
    local candidate="" line=""
    for candidate in \
        "${BASE:-}/config/service/clamav/scan.conf" \
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

set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -r "${HERE}/watchdog.conf" ]]; then
    # shellcheck disable=SC1091
    source "${HERE}/watchdog.conf"
fi
if [[ -z "${BASE:-}" && -z "${CONFIG_BASE_DIRECTORY:-}" && -n "${CONFIG_BASE_DIRECTORY+x}" ]]; then
    exit 0
fi
# shellcheck disable=SC1091
source "${HERE}/common.sh"
if [[ -z "${BASE:-}" ]]; then
    BASE="${CONFIG_BASE_DIRECTORY:-/opt/liltress-workstation}"
fi
STAMP="${STAMP:-$(date +%Y%m%d-%H%M%S)}"
LOG_DIR="${LOG_DIR:-${BASE}/cron/security_logs}"
ALERT_DIR="${ALERT_DIR:-${BASE}/cron/alerts}"
mkdir -p -- "${LOG_DIR}" "${ALERT_DIR}"
LOG_FILE="${LOG_DIR}/integrity-${STAMP}.log"
ALERT_FILE="${ALERT_DIR}/integrity-${STAMP}.txt"
MODULE_NAME="Integrite"
if ! declare -F log_pass >/dev/null 2>&1; then
    log_pass() { printf '%s\n' "$*"; }
fi

list=""
for candidate in \
    "${BASE}/config/service/integrity/paths.list" \
    "${CONFIG_BASE_DIRECTORY:-}/config/service/integrity/paths.list" \
    "${INSTALL_DIRECTORY:-}/config/service/integrity/paths.list"; do
    [[ -f "${candidate}" ]] || continue
    list="${candidate}"
    break
done
if [[ -z "${list}" ]]; then
    log_pass "$(get_text watchdog.list-of-integrity-absent)"
    exit 0
fi

run_dir="$(read_scan_run_dir)"
if ! install -d -m 755 "${run_dir}" 2>/dev/null; then
    run_dir="${BASE}/cron"
    mkdir -p -- "${run_dir}"
fi
current="$(mktemp -p "${run_dir}")"
trap 'rm -f "${current}"' EXIT
if declare -F watchdog_runtime_file >/dev/null 2>&1; then
    stamp="$(watchdog_runtime_file "${BASE}" integrity.sha256)"
else
    stamp="${BASE}/cron/integrity.sha256"
fi
while read -r path; do
    [[ -n "${path}" && "${path}" != \#* && -f "${path}" ]] || continue
    sha256sum -- "${path}"
done <"${list}" | sort >"${current}"

if [[ ! -s "${stamp}" ]]; then
    mkdir -p -- "$(dirname -- "${stamp}")"
    cat "${current}" >"${stamp}"
    chmod 600 "${stamp}"
    log_pass "$(get_text watchdog.initial-fingerprint-written)"
    exit 0
fi
if cmp -s "${stamp}" "${current}"; then
    log_pass "$(get_text watchdog.integrity-unchanged)"
    exit 0
fi
comm -3 "${stamp}" "${current}" >>"${LOG_FILE}" || true
cat "${current}" >"${stamp}"
chmod 600 "${stamp}"
log_alert "$(get_text watchdog.integrity-fingerprint-changed)"
exit 0
