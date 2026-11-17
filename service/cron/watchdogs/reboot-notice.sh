#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/reboot-notice.sh
# Updated at : 2026-11-17
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Alert when a reboot is useful.
# Note       : The same text is not sent twice.
# -----------------------------------------------------------------------------


set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/common.sh"
LOG_FILE="${LOG_DIR}/reboot-notice-${STAMP}.log"
ALERT_FILE="${ALERT_DIR}/reboot-notice-${STAMP}.txt"
: >"${LOG_FILE}"
MODULE_NAME="reboot"
arm_crash_mail "avis de redémarrage"

body=""
if [[ -f /var/run/reboot-required ]]; then
    body="$(cat /var/run/reboot-required)"
fi
if [[ -f /var/run/reboot-required.pkgs ]]; then
    body="${body}"$'\n'"$(sed '/^$/d' /var/run/reboot-required.pkgs)"
fi
if command -v fwupdmgr >/dev/null 2>&1; then
    fw=""
    fw_rc=0
    fw="$(timeout 20 fwupdmgr get-updates 2>/dev/null)" || fw_rc=$?
    if [[ "${fw_rc}" -eq 0 && -n "${fw}" ]] && ! grep -qiE 'no updates available|no available firmware updates|no updatable devices' <<<"${fw}"; then
        body="${body}"$'\n'"${fw}"
    fi
fi
body="$(printf '%s' "${body}" | sed '/^$/d')"
if [[ -z "${body}" ]]; then
    log_pass "$(get_text watchdog.no-restart-useful)"
    exit 0
fi

seen="${BASE}/cron/reboot-notice.seen"
digest="$(printf '%s' "${body}" | sha256sum | awk '{print $1}')"
if [[ -f "${seen}" ]] && [[ "$(cat "${seen}")" == "${digest}" ]]; then
    log_pass "$(get_text watchdog.avis-of-restart-already-sent)"
    exit 0
fi
printf '%s\n' "${body}" >>"${LOG_FILE}"
log_alert "$(get_text watchdog.a-restart-is-useful-the-machine-was-not-restarte)"
umask 077
printf '%s\n' "${digest}" >"${seen}"
chmod 600 "${seen}"
