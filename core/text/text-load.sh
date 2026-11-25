#!/usr/bin/env bash
# =============================================================================
# File       : core/text/text-load.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Open the journal catalog and the language file nearest the caller.
# Note       : Eight parent directories are visited. A missing catalog stops the process.
# -----------------------------------------------------------------------------


# The first existing journal script is opened.
source_installed_text() {
    local directory="$1"
    local hops=0 candidate=""
    while [[ "${hops}" -lt 8 && "${directory}" != "/" ]]; do
        for candidate in \
            "${directory}/log.sh" \
            "${directory}/bin/log.sh" \
            "${directory}/core/log/log.sh" \
            "${directory}/share/core/log/log.sh"; do
            if [[ -f "${candidate}" ]]; then
                # shellcheck disable=SC1090
                source "${candidate}"
                return 0
            fi
        done
        directory="$(dirname -- "${directory}")"
        hops=$((hops + 1))
    done
    return 0
}

load_installed_text() {
    local caller="" directory="" hops=0 conf=""
    caller="$(cd -- "$(dirname -- "${BASH_SOURCE[1]}")" && pwd)"
    source_installed_text "${caller}"
    if ! declare -F get_text >/dev/null 2>&1; then
        printf '%s\n' "get_text absent" >&2
        exit 1
    fi
    directory="${caller}"
    while [[ "${hops}" -lt 8 && "${directory}" != "/" ]]; do
        conf="${directory}/config/global.conf"
        if [[ -f "${conf}" ]]; then
            read_language_file "${conf}"
            break
        fi
        directory="$(dirname -- "${directory}")"
        hops=$((hops + 1))
    done
}
