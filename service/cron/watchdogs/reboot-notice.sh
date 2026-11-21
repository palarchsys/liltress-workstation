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

pkgs=""
if [[ -f /var/run/reboot-required.pkgs ]]; then
    pkgs="$(sed '/^$/d' /var/run/reboot-required.pkgs)"
fi
if [[ ! -f /var/run/reboot-required && -z "${pkgs}" ]]; then
    log_pass "$(get_text watchdog.no-restart-useful)"
    exit 0
fi

seen="${BASE}/cron/reboot-notice.seen"
digest="$(printf '%s' "${pkgs}" | sha256sum | awk '{print $1}')"
if [[ -f "${seen}" ]] && [[ "$(cat "${seen}")" == "${digest}" ]]; then
    log_pass "$(get_text watchdog.avis-of-restart-already-sent)"
    exit 0
fi
TITLE="$(get_text alert.mail.reboot.title)"
MAIL_EXTRA="${pkgs}"
MAIL_EXTRA_TITLE="$(get_text mail.reboot.packages)"
MAIL_JOURNAL_ONLY=1
export TITLE MAIL_EXTRA MAIL_EXTRA_TITLE MAIL_JOURNAL_ONLY
log_alert "$(get_text watchdog.a-restart-is-useful-the-machine-was-not-restarte)"
umask 077
printf '%s\n' "${digest}" >"${seen}"
chmod 600 "${seen}"
