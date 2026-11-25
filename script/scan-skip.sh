#!/usr/bin/env bash
# =============================================================================
# File       : script/scan-skip.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Maintain paths kept out of the on-access scanner.
# Note       : The command accepts three actions.
# -----------------------------------------------------------------------------


# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../core/boot/python.sh"

load_scan_skip_text() {
    local _text_directory _text_hops
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
}

init_scan_skip() {
    load_scan_skip_text
    if ! declare -F load_installed_text >/dev/null 2>&1; then
        printf '%s\n' "get_text absent" >&2
        exit 1
    fi
    load_installed_text
    if [[ -z "${BASE:-}" ]]; then
        BASE="${CONFIG_BASE_DIRECTORY:-/opt/liltress-workstation}"
    fi
    # shellcheck disable=SC1091
    source "${BASE}/service/cron/watchdogs/scan-skip-lib.sh"
    if [[ "${EUID}" -ne 0 ]]; then
        printf "$(get_text log.run-this-command-with-sudo-n)" >&2
        exit 1
    fi
}

show_usage() {
    printf "$(get_text log.usage-sudo-bash-bin-scan-skip-sh-list "${BASE}")" >&2
    printf "$(get_text log.sudo-bash-bin-scan-skip-sh-add-chemin "${BASE}")" >&2
    printf "$(get_text log.sudo-bash-bin-scan-skip-sh-del-chemin "${BASE}")" >&2
}

show_scan_skip_list() {
    local line
    collect_scan_skip_path
    if [[ ${#SCAN_SKIP_VALID[@]} -gt 0 ]]; then
        printf '%s\n' "${SCAN_SKIP_VALID[@]}"
    fi
    if [[ ${#SCAN_SKIP_BAD[@]} -gt 0 ]]; then
        for line in "${SCAN_SKIP_BAD[@]}"; do
            printf "$(get_text log.path-denied "${line}")" >&2
        done
    fi
}

record_scan_skip_found() {
    local path
    found=0
    if [[ ${#SCAN_SKIP_VALID[@]} -gt 0 ]]; then
        for path in "${SCAN_SKIP_VALID[@]}"; do
            [[ "${path}" == "${norm}" ]] && found=1
        done
    fi
}

write_scan_skip_change() {
    if [[ "${action}" == "add" ]]; then
        if [[ "${found}" -eq 1 ]]; then
            printf "$(get_text log.this-path-is-already-excluded-s-n)" "${norm}"
            exit 0
        fi
        if [[ -s "${SCAN_SKIP_FILE}" ]] && [[ "$(tail -c1 "${SCAN_SKIP_FILE}" | wc -l)" -eq 0 ]]; then
            printf "$(get_text log.n)" >>"${SCAN_SKIP_FILE}"
        fi
        printf '%s\n' "${norm}" >>"${SCAN_SKIP_FILE}"
        printf "$(get_text log.path-added "${norm}")"
    else
        if [[ "${found}" -eq 0 ]]; then
            printf '%s\n' "$(get_text log.path-absent-of-the-list "${norm}")" >&2
            exit 1
        fi
        python3 "$(locate_python_directory)/scan-skip-path.py" edit "${SCAN_SKIP_FILE}" "${norm}"
        printf "$(get_text log.path-removed "${norm}")"
    fi
    bash "${BASE}/service/cron/watchdogs/apply-scan-skip.sh"
    exit 0
}

set -euo pipefail

init_scan_skip
action="${1:-}"
case "${action}" in
    list | add | del) ;;
    *)
        show_usage
        exit 1
        ;;
esac
if [[ ! -f "${SCAN_SKIP_FILE}" ]]; then
    printf "$(get_text log.file-absent "${SCAN_SKIP_FILE}")" >&2
    exit 1
fi
if [[ "${action}" == "list" ]]; then
    show_scan_skip_list
    exit 0
fi
if [[ $# -ne 2 ]]; then
    show_usage
    exit 1
fi
if ! norm="$(check_scan_skip_path "$2")"; then
    printf "$(get_text log.path-denied "$2")" >&2
    exit 1
fi
collect_scan_skip_path
record_scan_skip_found
write_scan_skip_change
