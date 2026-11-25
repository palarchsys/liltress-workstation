#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/record-mirrors.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Store a digest of the mirror file. Another mode compares it.
# Note       : The stamp mode is 600.
# -----------------------------------------------------------------------------


load_mirror_base() {
    local here="" directory="" hops=0
    here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -r "${here}/watchdog.conf" ]]; then
        # shellcheck disable=SC1091
        source "${here}/watchdog.conf"
    fi
    directory="${here}"
    while [[ -z "${BASE:-}" && -z "${CONFIG_BASE_DIRECTORY:-}" && "${hops}" -lt 8 && "${directory}" != "/" ]]; do
        if [[ -f "${directory}/config/global.conf" ]]; then
            # shellcheck disable=SC1091
            source "${directory}/config/global.conf"
            return 0
        fi
        directory="$(dirname -- "${directory}")"
        hops=$((hops + 1))
    done
}
set -euo pipefail

load_mirror_base
if [[ -z "${BASE:-}" ]]; then
    BASE="${CONFIG_BASE_DIRECTORY:-/opt/liltress-workstation}"
fi
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
printf '%s\n' "${current}" >"${stamp}"
chmod 600 "${stamp}"
