#!/usr/bin/env bash
# =============================================================================
# File       : core/text/text-load.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Open the journal catalog and the language file nearest the caller.
# Note       : Eight parent directories are visited. A missing catalog stops the process.
# -----------------------------------------------------------------------------


# The first existing journal script is opened.
source_installed_text() {
    local dir="$1"
    local hops=0 candidate=""
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        for candidate in \
            "${dir}/log.sh" \
            "${dir}/bin/log.sh" \
            "${dir}/core/log/log.sh" \
            "${dir}/share/core/log/log.sh"; do
            if [[ -f "${candidate}" ]]; then
                # shellcheck disable=SC1090
                source "${candidate}"
                return 0
            fi
        done
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    return 0
}

load_installed_text() {
    local caller="" dir="" hops=0 conf=""
    caller="$(cd -- "$(dirname -- "${BASH_SOURCE[1]}")" && pwd)"
    source_installed_text "${caller}"
    if ! declare -F get_text >/dev/null 2>&1; then
        printf '%s\n' "get_text absent" >&2
        exit 1
    fi
    dir="${caller}"
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
