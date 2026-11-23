#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/scan-usbguard.sh
# Updated at : 2026-11-23
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Alert when USBGuard blocked a device during the last hour.
# -----------------------------------------------------------------------------


run_scan_usbguard_part_01() {
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
    source "${HERE}/common.sh" || exit 1
    if [[ -z "${BASE:-}" ]]; then
        BASE="${CONFIG_BASE_DIRECTORY:-/opt/liltress-workstation}"
    fi
}

run_scan_usbguard_part_02() {
    [[ "${USBGUARD_ENABLE:-1}" == "1" ]] || exit 0
    hits="$(journalctl -u usbguard --since "70 minutes ago" --no-pager 2>/dev/null | grep -Ei 'block|deny|reject' || true)"
    [[ -n "${hits}" ]] || exit 0
    STAMP="${STAMP:-$(date +%Y%m%d-%H%M%S)}"
    LOG_DIR="${LOG_DIR:-${BASE}/cron/security_logs}"
    ALERT_DIR="${ALERT_DIR:-${BASE}/cron/alerts}"
    mkdir -p -- "${LOG_DIR}" "${ALERT_DIR}"
    LOG_FILE="${LOG_DIR}/usbguard-${STAMP}.log"
    ALERT_FILE="${ALERT_DIR}/usbguard-${STAMP}.txt"
    printf '%s\n%s\n' "$(get_text hardening.usbguard.body)" "$(printf '%s\n' "${hits}" | head -n 40)" >"${LOG_FILE}"
    MODULE_NAME="USBGuard"
    log_alert "$(get_text hardening.usbguard.title)"
    exit 0
}

run_scan_usbguard_part_03() {
    run_scan_usbguard_part_01 "$@"
    run_scan_usbguard_part_02 "$@"
}

run_scan_usbguard_part_03 "$@"
