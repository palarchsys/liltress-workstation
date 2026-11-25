#!/usr/bin/env bash
# =============================================================================
# File       : core/quarantine/restore.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Put one recorded file back at its original path.
# Note       : The registry line is the only accepted origin.
# -----------------------------------------------------------------------------


restore_quarantine_01_run_01_read() {
    set -euo pipefail
    script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    for candidate in \
        "${script_directory}/log.sh" \
        "${script_directory}/../log/log.sh" \
        "${script_directory}/../core/log/log.sh" \
        "${CONFIG_BASE_DIRECTORY:-}/core/log/log.sh" \
        "${INSTALL_DIRECTORY:-}/core/log/log.sh" \
        "${INSTALL_DIRECTORY:-}/core/log/log.sh"; do
        if [[ -n "${candidate}" && -f "${candidate}" ]]; then
            # shellcheck disable=SC1090
            source "${candidate}"
            break
        fi
    done
    if [[ "$(basename -- "${script_directory}")" == "bin" ]]; then
        base="$(dirname -- "${script_directory}")"
    else
        base="${CONFIG_BASE_DIRECTORY:-${BASE:-/opt/liltress}}"
    fi
    if [[ -f "${base}/config/global.conf" ]] && declare -F read_language_file >/dev/null 2>&1; then
        read_language_file "${base}/config/global.conf"
    fi
}

restore_quarantine_01_run_02_get() {
    if [[ "${EUID}" -ne 0 ]]; then
        if declare -F get_text >/dev/null 2>&1; then
            printf '%s\n' "$(get_text log.root-required)" >&2
        else
            printf '%s\n' "root required" >&2
        fi
        exit 1
    fi
    if [[ "$#" -ne 1 || -z "${1:-}" ]]; then
        printf '%s\n' "$(get_text quarantine.identifier-required)" >&2
        exit 1
    fi
    id="$1"
    if [[ ! "${id}" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+- ]]; then
        printf '%s\n' "$(get_text quarantine.identifier-rejected)" >&2
        exit 1
    fi
    case "${id}" in
        */* | *\\*)
            printf '%s\n' "$(get_text quarantine.identifier-rejected)" >&2
            exit 1
            ;;
    esac
}

restore_quarantine_01_run_03_get() {
    if ! declare -F get_watchdog_runtime_file >/dev/null 2>&1; then
        for candidate in \
            "${script_directory}/../core/watchdog/base.sh" \
            "${base}/core/watchdog/base.sh" \
            "${base}/core/watchdog/base.sh"; do
            if [[ -f "${candidate}" ]]; then
                # shellcheck disable=SC1090
                source "${candidate}"
                break
            fi
        done
    fi
    if declare -F get_watchdog_runtime_file >/dev/null 2>&1; then
        registry="$(get_watchdog_runtime_file "${base}" quarantine.registry)"
    else
        registry="${base}/cron/quarantine.registry"
    fi
    if [[ ! -f "${registry}" ]]; then
        printf '%s\n' "$(get_text quarantine.identifier-absent-of-the-registre)" >&2
        exit 1
    fi
    line="$(awk -F '\t' -v want="${id}" '$1 == want { print; exit }' "${registry}")"
    if [[ -z "${line}" ]]; then
        printf '%s\n' "$(get_text quarantine.identifier-absent-of-the-registre)" >&2
        exit 1
    fi
    IFS=$'\t' read -r found_id _moment _source origin stored _signature <<<"${line}"
}

restore_quarantine_01_run_04_get() {
    if [[ "${found_id}" != "${id}" || -z "${origin}" || -z "${stored}" ]]; then
        printf '%s\n' "$(get_text quarantine.identifier-absent-of-the-registre)" >&2
        exit 1
    fi
    case "${origin}" in
        /*) ;;
        *)
            printf '%s\n' "$(get_text quarantine.location-original-rejected)" >&2
            exit 1
            ;;
    esac
    if [[ ! -e "${stored}" ]]; then
        printf '%s\n' "$(get_text quarantine.file-of-quarantine-absent)" >&2
        exit 1
    fi
    parent="$(dirname -- "${origin}")"
    if [[ ! -d "${parent}" ]]; then
        printf '%s\n' "$(get_text quarantine.directory-original-absent)" >&2
        exit 1
    fi
}

restore_quarantine_01_run_05_get() {
    if [[ -e "${origin}" ]]; then
        printf '%s\n' "$(get_text quarantine.location-original-busy)" >&2
        exit 1
    fi
    mv -- "${stored}" "${origin}"
    printf '%s\n' "$(get_text quarantine.file-reset-in-place)"
    exit 0
}

restore_quarantine_01_run_06_run() {
    restore_quarantine_01_run_01_read "$@"
    restore_quarantine_01_run_02_get "$@"
    restore_quarantine_01_run_03_get "$@"
    restore_quarantine_01_run_04_get "$@"
    restore_quarantine_01_run_05_get "$@"
}

restore_quarantine_01_run_06_run "$@"
