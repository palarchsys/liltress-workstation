#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/load.sh
# Updated at : 2026-11-05
# Creator    : palarchsys
# =============================================================================

source_text_engine() {
    local origin="$1"
    local candidate="" dir="" hops=0 product=""
    if declare -F get_text >/dev/null 2>&1; then
        return 0
    fi
    if [[ -z "${PRODUCT_ROOT:-}" ]]; then
        dir="${origin}"
        while [[ -n "${dir}" && "${dir}" != "/" && "${hops}" -lt 16 ]]; do
            if [[ -d "${dir}/locale/en" && -f "${dir}/core/log/log.sh" ]]; then
                product="${dir}"
                break
            fi
            dir="$(dirname -- "${dir}")"
            hops=$((hops + 1))
        done
        if [[ -n "${product}" ]]; then
            PRODUCT_ROOT="${product}"
            export PRODUCT_ROOT
        fi
    fi
    for candidate in \
        "${origin}/../log/log.sh" \
        "${BASE:-}/core/log/log.sh" \
        "${CONFIG_BASE_DIRECTORY:-}/core/log/log.sh" \
        "${PRODUCT_ROOT:-}/core/log/log.sh" \
        "${origin}/log.sh" \
        "${origin}/../../../core/log/log.sh" \
        "${origin}/../../../../share/core/log/log.sh"
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
    local candidate="" engine=""
    engine="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    source_text_engine "${engine}" || source_text_engine "${here}" || true
    for candidate in \
        "${engine}/watchdog.sh" \
        "${BASE:-}/core/watchdog/watchdog.sh" \
        "${CONFIG_BASE_DIRECTORY:-}/core/watchdog/watchdog.sh" \
        "${here}/../../../core/watchdog/watchdog.sh" \
        "${here}/../../../../share/core/watchdog/watchdog.sh"
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
