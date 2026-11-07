#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/record-mirrors.sh
# Updated at : 2026-10-28
# Creator    : palarchsys
# =============================================================================

set -euo pipefail

BASE="${BASE:-/opt/liltress-workstation}"
file="/var/lib/rkhunter/db/mirrors.dat"
stamp="${BASE}/cron/rkhunter-mirrors.sha256"
mode="${1:-save}"

if [[ ! -f "${file}" ]]; then
    exit 0
fi

current="$(sha256sum "${file}" | awk 'NR==1 { print $1 }')"

if [[ "${mode}" == "check" ]]; then
    if [[ ! -f "${stamp}" ]]; then
        exit 0
    fi
    saved="$(awk 'NR==1 { print $1 }' "${stamp}")"
    [[ "${current}" == "${saved}" ]]
    exit $?
fi

if [[ "${mode}" != "save" ]]; then
    printf 'Usage : %s check|save\n' "$0" >&2
    exit 2
fi

umask 077
printf '%s\n' "${current}" > "${stamp}"
chmod 600 "${stamp}"
