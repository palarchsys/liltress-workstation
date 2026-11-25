#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/common.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Load the shared watchdog helpers once.
# Note       : A second visit returns immediately.
# -----------------------------------------------------------------------------


common_watchdog_01_run_01_run() {
    set -euo pipefail
    if [[ -n "${LILTRESS_COMMON_LOADED:-}" ]]; then
        return 0
    fi
    LILTRESS_COMMON_LOADED=1
    # A watchdog.conf beside this file wins. Otherwise the nearest global.conf does.
}

# The nearest global.conf above this file supplies the product.
load_common_global() {
    local directory="$1"
    local hops=0
    while [[ -n "${directory}" && "${directory}" != "/" && "${hops}" -lt 8 ]]; do
        if [[ -f "${directory}/config/global.conf" ]]; then
            # shellcheck disable=SC1091
            source "${directory}/config/global.conf"
            return 0
        fi
        directory="$(dirname -- "${directory}")"
        hops=$((hops + 1))
    done
}

load_common_product() {
    local directory=""
    directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -r "${directory}/watchdog.conf" ]]; then
        # shellcheck disable=SC1091
        source "${directory}/watchdog.conf"
    fi
    if [[ -n "${BASE:-}" || -n "${CONFIG_BASE_DIRECTORY:-}" ]]; then
        return 0
    fi
    load_common_global "${directory}"
}

common_watchdog_01_run_02_load() {
    load_common_product
    if [[ -z "${BASE:-}" ]]; then
        BASE="${CONFIG_BASE_DIRECTORY:-/opt/liltress-workstation}"
    fi
    LOG_DIR="${BASE}/cron/security_logs"
    ALERT_DIR="${BASE}/cron/alerts"
    mkdir -p "${LOG_DIR}" "${ALERT_DIR}"
    STAMP="$(date +%Y%m%d-%H%M%S)"
    if [[ -z "${MAIL_ALERTS:-}" && -f "${BASE}/config/global.conf" ]]; then
        INSTALL_DIRECTORY="${BASE}"
        # shellcheck disable=SC1091
        source "${BASE}/config/global.conf"
    fi
    if [[ -z "${WATCHDOG_MAIL:-}" && -r "${BASE}/config/secrets.conf" ]]; then
        # shellcheck disable=SC1091
        source "${BASE}/config/secrets.conf"
    fi
}

log_pass() { printf '%s %s\n' "$(date -Iseconds)" "$*" | tee -a "${LOG_FILE}"; }

common_watchdog_01_run_03_load() {
    here_watchdog="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    for candidate_watchdog in \
        "${BASE:-}/core/watchdog/load.sh" \
        "${here_watchdog}/../../core/watchdog/load.sh" \
        "${INSTALL_DIRECTORY:-}/core/watchdog/load.sh" \
        "${CONFIG_BASE_DIRECTORY:-}/core/watchdog/load.sh"; do
        if [[ -n "${candidate_watchdog}" && -f "${candidate_watchdog}" ]]; then
            # shellcheck disable=SC1090
            source "${candidate_watchdog}"
            break
        fi
    done
}

common_watchdog_01_run_04_load() {
    if ! declare -F load_shared_watchdog >/dev/null 2>&1; then
        directory_watchdog="${here_watchdog}"
        hops_watchdog=0
        while [[ -n "${directory_watchdog}" && "${directory_watchdog}" != "/" && "${hops_watchdog}" -lt 16 ]]; do
            if [[ -f "${directory_watchdog}/core/watchdog/load.sh" ]]; then
                # shellcheck disable=SC1090
                source "${directory_watchdog}/core/watchdog/load.sh"
                break
            fi
            directory_watchdog="$(dirname -- "${directory_watchdog}")"
            hops_watchdog=$((hops_watchdog + 1))
        done
    fi
}

common_watchdog_01_run_05_load() {
    if declare -F load_shared_watchdog >/dev/null 2>&1; then
        load_shared_watchdog "${here_watchdog}" || exit 1
    else
        printf '%s\n' "watchdog-load.sh not found" >&2
        exit 1
    fi
    if declare -F read_language_file >/dev/null 2>&1 && [[ -f "${BASE}/config/global.conf" ]]; then
        read_language_file "${BASE}/config/global.conf"
    fi
}

common_watchdog_01_run_06_run() {
    common_watchdog_01_run_03_load "$@"
    common_watchdog_01_run_04_load "$@"
    common_watchdog_01_run_05_load "$@"
}

common_watchdog_01_run_01_run "$@"

common_watchdog_01_run_02_load "$@"

common_watchdog_01_run_06_run "$@"
