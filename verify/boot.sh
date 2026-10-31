#!/usr/bin/env bash
# =============================================================================
# File       : verify/boot.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

if [[ "${EUID}" -ne 0 ]]; then
    printf "$(get_text log.run-this-command-with-sudo-n)" >&2
    exit 1
fi

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${here}/../service/cron/boot-check.sh"
