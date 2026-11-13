#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/integrity.sh
# Updated at : 2026-11-13
# Creator    : palarchsys
# =============================================================================
# -----------------------------------------------------------------------------
# Note       : The stamp lives under the Liltress cron directory.
# Note       : The first pass writes the stamp and stays silent.
# -----------------------------------------------------------------------------

set -euo pipefail
BASE="${BASE:-/opt/liltress-workstation}"
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"
LOG_FILE="${LOG_DIR}/integrity-${STAMP}.log"
ALERT_FILE="${ALERT_DIR}/integrity-${STAMP}.txt"
MODULE_NAME="Integrite"

list=""
for candidate in \
    "${BASE}/config/integrity/paths.list" \
    "${BASE}/config/integrity/paths.list" \
    "${INSTALL_DIRECTORY:-}/config/integrity/paths.list"
do
    [[ -f "${candidate}" ]] || continue
    list="${candidate}"
    break
done
if [[ -z "${list}" ]]; then
    log_pass "$(get_text watchdog.list-of-integrity-absent)"
    exit 0
fi

install -d -m 755 /run/liltress-workstation
current="$(mktemp -p /run/liltress-workstation)"
trap 'rm -f "${current}"' EXIT
if declare -F watchdog_runtime_file >/dev/null 2>&1; then
    stamp="$(watchdog_runtime_file "${BASE}" integrity.sha256)"
else
    stamp="${BASE}/cron/integrity.sha256"
fi
while read -r path; do
    [[ -n "${path}" && "${path}" != \#* && -f "${path}" ]] || continue
    sha256sum -- "${path}"
done < "${list}" | sort > "${current}"

if [[ ! -s "${stamp}" ]]; then
    mkdir -p -- "$(dirname -- "${stamp}")"
    cat "${current}" > "${stamp}"
    chmod 600 "${stamp}"
    log_pass "$(get_text watchdog.initial-fingerprint-written)"
    exit 0
fi
if cmp -s "${stamp}" "${current}"; then
    log_pass "$(get_text watchdog.integrity-unchanged)"
    exit 0
fi
comm -3 "${stamp}" "${current}" >> "${LOG_FILE}" || true
cat "${current}" > "${stamp}"
chmod 600 "${stamp}"
log_alert "$(get_text watchdog.integrity-fingerprint-changed)"
exit 0
