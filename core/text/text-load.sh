#!/usr/bin/env bash
# =============================================================================
# File       : core/text/text-load.sh
# Updated at : 2026-11-06
# Creator    : palarchsys
# =============================================================================

load_installed_text() {
    local caller dir hops candidate conf
    caller="$(cd -- "$(dirname -- "${BASH_SOURCE[1]}")" && pwd)"
    dir="${caller}"
    hops=0
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        for candidate in \
            "${dir}/log.sh" \
            "${dir}/bin/log.sh" \
            "${dir}/cron/bin/log.sh" \
            "${dir}/src/core/log/log.sh" \
            "${dir}/core/log/log.sh" \
            "${dir}/share/core/log/log.sh"
        do
            if [[ -f "${candidate}" ]]; then
                # shellcheck disable=SC1090
                source "${candidate}"
                break 2
            fi
        done
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    if ! declare -F get_text >/dev/null 2>&1; then
        printf '%s\n' "get_text absent" >&2
        exit 1
    fi
    dir="${caller}"
    hops=0
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        conf="${dir}/config/global.conf"
        if [[ -f "${conf}" ]]; then
            read_language_file "${conf}"
            break
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
}
