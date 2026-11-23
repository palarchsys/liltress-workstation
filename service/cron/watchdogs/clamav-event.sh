#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/clamav-event.sh
# Updated at : 2026-11-23
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Raise an alert when an on-access virus event arrives.
# -----------------------------------------------------------------------------


read_logger_tag() {
    local tag="${BASE:-liltress}"
    tag="${tag##*/}"
    if [[ -z "${tag}" ]]; then
        tag="liltress"
    fi
    printf '%s\n' "${tag}"
}

run_clamav_event_part_01() {
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
    file="${CLAM_VIRUSEVENT_FILENAME:-inconnu}"
    virus="${CLAM_VIRUSEVENT_VIRUSNAME:-inconnu}"
    base="$(basename -- "${file}")"
}

run_clamav_event_part_02() {
    [[ -n "${base}" && "${base}" != "/" ]] || base="inconnu"
    case "${base}" in
        .clamav-quarantine-lock.*) exit 0 ;;
    esac
    LOG_FILE="${LOG_DIR}/clamav-onaccess-${STAMP}.log"
    ALERT_FILE="${ALERT_DIR}/clamav-onaccess-${STAMP}.txt"
    MODULE_NAME="Clamav"
    export LOG_FILE ALERT_FILE MODULE_NAME BASE
    export CLAMAV_EVENT_FILE="${file}"
    export CLAMAV_EVENT_VIRUS="${virus}"
    export CLAMAV_EVENT_KIND=onaccess
    export CLAMAV_EVENT_MAIL=1
    export CLAMAV_RESPONSE_STAMP="${STAMP}"
    response="${BASE}/service/cron/watchdogs/clamav-response.sh"
    if [[ ! -x "${response}" ]]; then
        response="${HERE}/clamav-response.sh"
    fi
    bash "${response}" || true
    if [[ -f "${LOG_DIR}/clamav-response-${STAMP}.path" ]]; then
        CLAMAV_QUARANTINE="$(cat "${LOG_DIR}/clamav-response-${STAMP}.path")"
        export CLAMAV_QUARANTINE
    fi
    arm_crash_mail "ClamAV accès"
    logger -t "$(read_logger_tag)" -p auth.warning "ClamAV ${virus} origine=${file} quarantaine=${CLAMAV_QUARANTINE:-inconnue}"
    log_alert "$(get_text watchdog.clamav-in "${virus}" "${file}")"
}

run_clamav_event_part_03() {
    run_clamav_event_part_01 "$@"
    run_clamav_event_part_02 "$@"
}

run_clamav_event_part_03 "$@"
