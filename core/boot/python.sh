#!/usr/bin/env bash
# =============================================================================
# File       : core/boot/python.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Find the shared Python directory without loading the engine.
# Note       : shown_python stays visible to the caller.
# -----------------------------------------------------------------------------


# The caller owns shown_python and reads it after this call.
show_python_directory() {
    local candidate="$1"
    shown_python=0
    [[ -n "${candidate}" && -d "${candidate}" ]] || return 0
    (cd -- "${candidate}" && pwd -P)
    shown_python=1
    return 0
}

# The shared directory is printed as given, without resolving links.
show_share_python() {
    local directory="$1"
    shown_python=0
    if [[ ! -d "${directory}/share/python" ]]; then
        return 0
    fi
    printf '%s\n' "${directory}/share/python"
    shown_python=1
    return 0
}

locate_python_directory() {
    local directory="" hops=0 candidate="" shown_python=0
    for candidate in \
        "${CONFIG_BASE_DIRECTORY:-}/python" \
        "${BASE:-}/python" \
        "${INSTALL_DIRECTORY:-}/python" \
        "${INSTALL_DIRECTORY:-}/../share/python"; do
        show_python_directory "${candidate}"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
    done
    directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${directory}" != "/" ]]; do
        show_share_python "${directory}"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
        show_python_directory "${directory}/python"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
        directory="$(dirname -- "${directory}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}
