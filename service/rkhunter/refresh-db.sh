#!/usr/bin/env bash
# =============================================================================
# File       : service/rkhunter/refresh-db.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Rebuild the rootkit hunter property database.
# -----------------------------------------------------------------------------


rkhunter_refresh_db_01_run_01_load() {
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
}

rkhunter_refresh_db_01_run_02_get() {
    if [[ "${EUID}" -ne 0 ]]; then
        printf "$(get_text log.run-this-command-with-sudo-n)" >&2
        exit 1
    fi
    if ! command -v rkhunter >/dev/null 2>&1; then
        printf "$(get_text log.rkhunter-is-absent-n)" >&2
        exit 1
    fi
    printf "$(get_text log.calculation-of-the-properties-baseline-rkhunter)"
    set +e
    rkhunter --propupd --nocolors
    rc=$?
    set -e
    if [[ "${rc}" -ne 0 ]]; then
        printf "$(get_text log.rkhunter-propupd-a-returned-the-code "${rc}")" >&2
        exit 1
    fi
    printf "$(get_text log.properties-baseline-rkhunter-saved-n)"
}

rkhunter_refresh_db_01_run_03_run() {
    rkhunter_refresh_db_01_run_01_load "$@"
    rkhunter_refresh_db_01_run_02_get "$@"
}

rkhunter_refresh_db_01_run_03_run "$@"
