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


source_python_boot() {
    local dir hops
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    hops=0
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        if [[ -f "${dir}/core/boot/python.sh" ]]; then
            # shellcheck disable=SC1090
            source "${dir}/core/boot/python.sh"
            return 0
        fi
        if [[ -f "${dir}/share/core/boot/python.sh" ]]; then
            # shellcheck disable=SC1090
            source "${dir}/share/core/boot/python.sh"
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

source_python_boot

load_scan_skip_text() {
    local _text_dir _text_hops
    _text_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    _text_hops=0
    while [[ "${_text_hops}" -lt 8 && "${_text_dir}" != "/" ]]; do
        if [[ -f "${_text_dir}/text-load.sh" ]]; then
            # shellcheck disable=SC1090
            source "${_text_dir}/text-load.sh"
            break
        fi
        if [[ -f "${_text_dir}/share/core/text/text-load.sh" ]]; then
            # shellcheck disable=SC1090
            source "${_text_dir}/share/core/text/text-load.sh"
            break
        fi
        if [[ -f "${_text_dir}/core/text/text-load.sh" ]]; then
            # shellcheck disable=SC1090
            source "${_text_dir}/core/text/text-load.sh"
            break
        fi
        _text_dir="$(dirname -- "${_text_dir}")"
        _text_hops=$((_text_hops + 1))
    done
}

prepare_scan_skip() {
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

mark_scan_skip_found() {
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
        python3 "$(locate_python_dir)/scan-skip-path.py" edit "${SCAN_SKIP_FILE}" "${norm}"
        printf "$(get_text log.path-removed "${norm}")"
    fi
    bash "${BASE}/service/cron/watchdogs/apply-scan-skip.sh"
    exit 0
}

set -euo pipefail

prepare_scan_skip
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
mark_scan_skip_found
write_scan_skip_change
