#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/common.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

set -euo pipefail
BASE="${BASE:-/opt/liltress-workstation}"
LOG_DIR="${BASE}/cron/security_logs"
ALERT_DIR="${BASE}/cron/alerts"
mkdir -p "${LOG_DIR}" "${ALERT_DIR}"
STAMP="$(date +%Y%m%d-%H%M%S)"
if [[ -f "${BASE}/cron/mail.conf" ]]; then
    # shellcheck disable=SC1091
    source "${BASE}/cron/mail.conf"
fi

log_pass()  { printf '%s %s\n' "$(date -Iseconds)" "$*" | tee -a "${LOG_FILE}"; }

here_watchdog="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
for candidate_watchdog in \
    "${here_watchdog}/../../../core/watchdog/load.sh" \
    "${here_watchdog}/../../../../share/core/watchdog/load.sh" \
    "${INSTALL_DIRECTORY:-}/core/watchdog/load.sh" \
    "${CONFIG_BASE_DIRECTORY:-}/src/core/watchdog/load.sh" \
    "${BASE:-}/src/core/watchdog/load.sh"
do
    if [[ -n "${candidate_watchdog}" && -f "${candidate_watchdog}" ]]; then
        # shellcheck disable=SC1090
        source "${candidate_watchdog}"
        break
    fi
done
if ! declare -F load_shared_watchdog >/dev/null 2>&1; then
    dir_watchdog="${here_watchdog}"
    hops_watchdog=0
    while [[ -n "${dir_watchdog}" && "${dir_watchdog}" != "/" && "${hops_watchdog}" -lt 16 ]]; do
        if [[ -f "${dir_watchdog}/src/core/watchdog/load.sh" ]]; then
            # shellcheck disable=SC1090
            source "${dir_watchdog}/src/core/watchdog/load.sh"
            break
        fi
        if [[ -f "${dir_watchdog}/core/watchdog/load.sh" ]]; then
            # shellcheck disable=SC1090
            source "${dir_watchdog}/core/watchdog/load.sh"
            break
        fi
        dir_watchdog="$(dirname -- "${dir_watchdog}")"
        hops_watchdog=$((hops_watchdog + 1))
    done
fi
if declare -F load_shared_watchdog >/dev/null 2>&1; then
    load_shared_watchdog "${here_watchdog}" || exit 1
elif [[ -f "${here_watchdog}/watchdog.sh" ]]; then
    # shellcheck disable=SC1091
    source "${here_watchdog}/watchdog.sh"
else
    printf '%s\n' "watchdog-load.sh not found" >&2
    exit 1
fi
if declare -F read_language_file >/dev/null 2>&1 && [[ -f "${BASE}/config/global.conf" ]]; then
    read_language_file "${BASE}/config/global.conf"
fi

