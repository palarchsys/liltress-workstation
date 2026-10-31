#!/usr/bin/env bash
# =============================================================================
# File       : service/rkhunter/refresh-db.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

set -euo pipefail
if [[ "${EUID}" -ne 0 ]]; then
    printf "$(get_text log.run-this-command-with-sudo-n)" >&2
    exit 1
fi
if ! command -v rkhunter >/dev/null 2>&1; then
    printf "$(get_text log.rkhunter-is-absent-n)" >&2
    exit 1
fi
printf "$(get_text log.calculation-of-the-properties-baseline-rkhunter)"
set +e
rkhunter --propupd --nocolors
rc=$?
set -e
if [[ "${rc}" -ne 0 ]]; then
    printf "$(get_text log.rkhunter-propupd-a-returned-the-code "${rc}")" >&2
    exit 1
fi
printf "$(get_text log.properties-baseline-rkhunter-saved-n)"
