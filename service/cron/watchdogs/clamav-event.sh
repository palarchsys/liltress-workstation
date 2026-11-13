#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/clamav-event.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

set -euo pipefail
BASE="${BASE:-/opt/liltress-workstation}"
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"
file="${CLAM_VIRUSEVENT_FILENAME:-inconnu}"
virus="${CLAM_VIRUSEVENT_VIRUSNAME:-inconnu}"
base="$(basename -- "${file}")"
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
    response="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/clamav-response.sh"
fi
bash "${response}" || true
if [[ -f "${LOG_DIR}/clamav-response-${STAMP}.path" ]]; then
    CLAMAV_QUARANTINE="$(cat "${LOG_DIR}/clamav-response-${STAMP}.path")"
    export CLAMAV_QUARANTINE
fi
arm_crash_mail "ClamAV accès"
logger -t liltress-workstation -p auth.warning "ClamAV ${virus} origine=${file} quarantaine=${CLAMAV_QUARANTINE:-inconnue}"
log_alert "$(get_text watchdog.clamav-in "${virus}" "${file}")"
