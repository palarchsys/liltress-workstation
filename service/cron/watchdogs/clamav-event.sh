#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/clamav-event.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

set -euo pipefail
W_BASE="${W_BASE:-/opt/liltress-workstation}"
# shellcheck disable=SC1091
source "${W_BASE}/cron/bin/common.sh"
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
export LOG_FILE ALERT_FILE MODULE_NAME W_BASE
export W_CLAMAV_EVENT_FILE="${file}"
export W_CLAMAV_EVENT_VIRUS="${virus}"
export W_CLAMAV_EVENT_KIND=onaccess
export W_CLAMAV_EVENT_MAIL=1
export W_CLAMAV_RESPONSE_STAMP="${STAMP}"
response="${W_BASE}/cron/bin/clamav-response.sh"
if [[ ! -x "${response}" ]]; then
    response="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/clamav-response.sh"
fi
bash "${response}" || true
if [[ -f "${LOG_DIR}/clamav-response-${STAMP}.path" ]]; then
    W_CLAMAV_QUARANTINE="$(cat "${LOG_DIR}/clamav-response-${STAMP}.path")"
    export W_CLAMAV_QUARANTINE
fi
arm_crash_mail "ClamAV accès"
logger -t liltress-workstation -p auth.warning "ClamAV ${virus} origine=${file} quarantaine=${W_CLAMAV_QUARANTINE:-inconnue}"
log_alert "$(get_text watchdog.clamav-in "${virus}" "${file}")"
