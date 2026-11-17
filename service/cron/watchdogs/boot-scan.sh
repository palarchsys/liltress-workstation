#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/boot-scan.sh
# Updated at : 2026-11-17
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Run the periodic chain, then arm access and the next pass.
# Note       : The reboot notice is last. It is not a scan.
# -----------------------------------------------------------------------------


run_boot_link() {
    local script="$1"
    local label="$2"
    local status=0
    if [[ ! -x "${HERE}/${script}" ]]; then
        return 0
    fi
    set +e
    bash "${HERE}/${script}"
    status=$?
    set -e
    if [[ "${status}" -ne 0 ]]; then
        log_alert "$(get_crash_sentence "${label}" "${status}")" || true
    fi
}

run_boot_scan() {
    run_boot_link chain-periodic.sh "chaîne"
    run_boot_link arm-onaccess.sh "accès"
    run_boot_link arm-periodic-scan.sh "période"
    run_boot_link reboot-notice.sh "avis de redémarrage"
}

set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -r "${HERE}/watchdog.conf" ]]; then
    # shellcheck disable=SC1091
    source "${HERE}/watchdog.conf"
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
LOG_FILE="${LOG_DIR}/boot-scan-${STAMP}.log"
ALERT_FILE="${ALERT_DIR}/boot-scan-${STAMP}.txt"
: >"${LOG_FILE}"
if [[ -f "${BASE}/cron/mail.conf" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${BASE}/cron/mail.conf"
    set +a
fi
export BASE
if [[ -n "${CONFIG_BASE_DIRECTORY:-}" ]]; then
    export CONFIG_BASE_DIRECTORY
fi
run_boot_scan
exit 0
