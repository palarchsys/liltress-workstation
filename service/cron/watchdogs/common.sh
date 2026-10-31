#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/common.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

set -euo pipefail
W_BASE="${W_BASE:-/opt/liltress-workstation}"
LOG_DIR="${W_BASE}/cron/security_logs"
ALERT_DIR="${W_BASE}/cron/alerts"
mkdir -p "${LOG_DIR}" "${ALERT_DIR}"
STAMP="$(date +%Y%m%d-%H%M%S)"
if [[ -f "${W_BASE}/cron/mail.conf" ]]; then
    # shellcheck disable=SC1091
    source "${W_BASE}/cron/mail.conf"
fi

log_pass()  { printf '%s %s\n' "$(date -Iseconds)" "$*" | tee -a "${LOG_FILE}"; }

source_text_engine() {
    local origin="$1"
    local candidate="" dir="" hops=0 product=""
    if declare -F get_text >/dev/null 2>&1; then
        return 0
    fi
    if [[ -z "${G_PRODUCT_ROOT:-}" ]]; then
        dir="${origin}"
        while [[ -n "${dir}" && "${dir}" != "/" && "${hops}" -lt 16 ]]; do
            if [[ -d "${dir}/locale/en" && -f "${dir}/core/log.sh" ]]; then
                product="${dir}"
                break
            fi
            dir="$(dirname -- "${dir}")"
            hops=$((hops + 1))
        done
        if [[ -n "${product}" ]]; then
            G_PRODUCT_ROOT="${product}"
            export G_PRODUCT_ROOT
        fi
    fi
    for candidate in \
        "${origin}/log.sh" \
        "${G_PRODUCT_ROOT:-}/core/log.sh" \
        "${origin}/../../../../core/log.sh" \
        "${origin}/../../../core/log.sh" \
        "${W_BASE:-}/src/core/log.sh" \
        "${G_BASE:-}/src/core/log.sh" \
        "${G_CONFIG_BASE_DIRECTORY:-}/src/core/log.sh" \
        "${G_INSTALL_DIRECTORY:-}/core/log.sh" \
        "${G_INSTALL_DIRECTORY:-}/src/core/log.sh" \
        "${G_PRODUCT_ROOT:-}/../core/log.sh"
    do
        if [[ -n "${candidate}" && -f "${candidate}" ]]; then
            # shellcheck disable=SC1090
            source "${candidate}"
            return 0
        fi
    done
    return 1
}

load_shared_watchdog() {
    local here="$1"
    local candidate=""
    source_text_engine "${here}" || true
    for candidate in \
        "${here}/watchdog.sh" \
        "${here}/../../../core/watchdog.sh" \
        "${here}/../../../../core/watchdog.sh" \
        "${W_BASE:-}/cron/bin/watchdog.sh" \
        "${G_CONFIG_BASE_DIRECTORY:-}/cron/bin/watchdog.sh"
    do
        if [[ -n "${candidate}" && -f "${candidate}" ]]; then
            # shellcheck disable=SC1090
            source "${candidate}"
            return 0
        fi
    done
    if declare -F get_text >/dev/null 2>&1; then
        printf '%s\n' "$(get_text log.watchdog-not-found)" >&2
    else
        printf '%s\n' "watchdog.sh not found" >&2
    fi
    return 1
}

load_shared_watchdog "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

