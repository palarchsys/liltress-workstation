#!/usr/bin/env bash
# =============================================================================
# File       : service/chkrootkit/ignore-log.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Record a chkrootkit journal in the ignore list.
# -----------------------------------------------------------------------------


# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../core/boot/python.sh"

chkrootkit_ignore_log_01_run_01_load() {
    set -euo pipefail
    _text_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    _text_hops=0
    while [[ "${_text_hops}" -lt 8 && "${_text_directory}" != "/" ]]; do
        if [[ -f "${_text_directory}/text-load.sh" ]]; then
            # shellcheck disable=SC1090
            source "${_text_directory}/text-load.sh"
            break
        fi
        if [[ -f "${_text_directory}/share/core/text/text-load.sh" ]]; then
            # shellcheck disable=SC1090
            source "${_text_directory}/share/core/text/text-load.sh"
            break
        fi
        if [[ -f "${_text_directory}/core/text/text-load.sh" ]]; then
            # shellcheck disable=SC1090
            source "${_text_directory}/core/text/text-load.sh"
            break
        fi
        _text_directory="$(dirname -- "${_text_directory}")"
        _text_hops=$((_text_hops + 1))
    done
    unset _text_directory _text_hops
    if ! declare -F load_installed_text >/dev/null 2>&1; then
        printf '%s\n' "get_text absent" >&2
        exit 1
    fi
    load_installed_text
    BASE="${BASE:-/opt/liltress-workstation}"
}

chkrootkit_ignore_log_01_run_02_get() {
    if [[ "${EUID}" -ne 0 ]]; then
        printf "$(get_text log.run-this-command-with-sudo-n)" >&2
        exit 1
    fi
    if [[ $# -ne 1 || ! -f "$1" ]]; then
        printf "$(get_text log.enter-the-journal-chkrootkit-named-in-l)"\''e-mail.\n' >&2
        printf "$(get_text log.example-sudo-bash-bin-chkrootkit-ignore-log-sh-c "${BASE}" "${BASE}")" >&2
        exit 1
    fi

    python3 "$(locate_python_directory)/chkrootkit-filter.py" ignore "${BASE}" "$1"
}

chkrootkit_ignore_log_01_run_03_run() {
    chkrootkit_ignore_log_01_run_01_load "$@"
    chkrootkit_ignore_log_01_run_02_get "$@"
}

chkrootkit_ignore_log_01_run_03_run "$@"
