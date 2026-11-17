#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/load.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Open the text catalog and the watchdog engine.
# Note       : An engine that is already open is left in place.
# -----------------------------------------------------------------------------


# The caller owns product. The walk stops at the first tree that holds the catalog and the journal.
locate_text_product() {
    local dir="$1"
    local hops=0
    product=""
    while [[ -n "${dir}" && "${dir}" != "/" && "${hops}" -lt 16 ]]; do
        if [[ -d "${dir}/locale/en" && -f "${dir}/core/log/log.sh" ]]; then
            product="${dir}"
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    return 0
}

# The caller owns text_sourced. The first existing file is loaded.
source_text_candidate() {
    local candidate=""
    text_sourced=0
    for candidate in "$@"; do
        if [[ -n "${candidate}" && -f "${candidate}" ]]; then
            # shellcheck disable=SC1090
            source "${candidate}"
            text_sourced=1
            return 0
        fi
    done
    return 0
}

source_text_engine() {
    local origin="$1"
    local product="" text_sourced=0
    if declare -F get_text >/dev/null 2>&1; then
        return 0
    fi
    if [[ -z "${PRODUCT_ROOT:-}" ]]; then
        locate_text_product "${origin}"
        if [[ -n "${product}" ]]; then
            PRODUCT_ROOT="${product}"
            export PRODUCT_ROOT
        fi
    fi
    source_text_candidate \
        "${origin}/../log/log.sh" \
        "${BASE:-}/core/log/log.sh" \
        "${CONFIG_BASE_DIRECTORY:-}/core/log/log.sh" \
        "${PRODUCT_ROOT:-}/core/log/log.sh" \
        "${origin}/log.sh" \
        "${origin}/../../../core/log/log.sh" \
        "${origin}/../../../../share/core/log/log.sh"
    [[ "${text_sourced}" -eq 1 ]] || return 1
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
        "${here}/../../../../share/core/watchdog/watchdog.sh"; do
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
