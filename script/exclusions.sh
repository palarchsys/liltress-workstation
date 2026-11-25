#!/usr/bin/env bash
# =============================================================================
# File       : script/exclusions.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Maintain one workstation exclusion list for the security tools.
# Note       : scan-skip.sh still owns the on-access home list.
# -----------------------------------------------------------------------------


read_exclusion_python() {
    local dir
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
    if [[ -d "${dir}/python" ]]; then
        printf '%s\n' "${dir}/python"
        return 0
    fi
    if [[ -d "${dir}/../share/python" ]]; then
        printf '%s\n' "${dir}/../share/python"
        return 0
    fi
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

load_exclusion_text() {
    local dir hops
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    hops=0
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        if [[ -f "${dir}/core/text/text-load.sh" ]]; then
            # shellcheck disable=SC1090
            source "${dir}/core/text/text-load.sh"
            return 0
        fi
        if [[ -f "${dir}/share/core/text/text-load.sh" ]]; then
            # shellcheck disable=SC1090
            source "${dir}/share/core/text/text-load.sh"
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
}

prepare_exclusion() {
    load_exclusion_text
    if ! declare -F get_text >/dev/null 2>&1; then
        printf '%s\n' "get_text absent" >&2
        exit 1
    fi
    load_installed_text
    if [[ -z "${BASE:-}" ]]; then
        BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
    fi
    export BASE
    EXCLUSION_FILE="${BASE}/config/service/exclusions/entries.yaml"
    if [[ "${EUID}" -ne 0 ]]; then
        printf "$(get_text log.run-this-command-with-sudo-n)" >&2
        exit 1
    fi
}

show_usage() {
    printf '%s\n' "$(get_text log.exclusion-usage)" >&2
}

report_exclusion_error() {
    case "$1" in
        path) printf '%s\n' "$(get_text log.exclusion-path)" >&2 ;;
        tools) printf '%s\n' "$(get_text log.exclusion-tools)" >&2 ;;
        reason) printf '%s\n' "$(get_text log.exclusion-reason)" >&2 ;;
        id) printf '%s\n' "$(get_text log.exclusion-absent)" >&2 ;;
        *) printf '%s\n' "$(get_text log.exclusion-yaml)" >&2 ;;
    esac
}

run_exclusion_apply() {
    local python dir
    python="$(read_exclusion_python)"
    dir="${BASE}/config/service/exclusions/generated"
    python3 "${python}/exclusions.py" render "${EXCLUSION_FILE}" "${dir}" "$(date +%F)"
    python3 "${python}/exclusions.py" splice /etc/aide/aide.conf "${dir}/aide.rules"
    python3 "${python}/exclusions.py" splice /etc/rkhunter.conf.local "${dir}/rkhunter-allow.conf"
    bash "${BASE}/service/cron/watchdogs/apply-scan-skip.sh"
    printf '%s\n' "$(get_text log.exclusion-applied)"
}

run_exclusion_add() {
    local path="" tools="" reason="" err id
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --path)
                path="${2:-}"
                shift 2
                ;;
            --tools)
                tools="${2:-}"
                shift 2
                ;;
            --reason)
                reason="${2:-}"
                shift 2
                ;;
            *)
                show_usage
                exit 1
                ;;
        esac
    done
    if [[ -z "${path}" || -z "${tools}" || -z "${reason}" ]]; then
        show_usage
        exit 1
    fi
    err="$(mktemp)"
    if ! id="$(python3 "$(read_exclusion_python)/exclusions.py" add "${EXCLUSION_FILE}" "${path}" "${tools}" "${reason}" "$(date +%F)" 2>"${err}")"; then
        report_exclusion_error "$(cat "${err}")"
        rm -f "${err}"
        exit 1
    fi
    rm -f "${err}"
    printf '%s\n' "$(get_text log.exclusion-added "${id}")"
    run_exclusion_apply
}

run_exclusion_list() {
    local tool=""
    if [[ "${1:-}" == "--tool" ]]; then
        tool="${2:-}"
        if [[ -z "${tool}" ]]; then
            show_usage
            exit 1
        fi
    elif [[ -n "${1:-}" ]]; then
        show_usage
        exit 1
    fi
    python3 "$(read_exclusion_python)/exclusions.py" list "${EXCLUSION_FILE}" "${tool}"
}

run_exclusion_remove() {
    local err
    if [[ $# -ne 1 ]]; then
        show_usage
        exit 1
    fi
    err="$(mktemp)"
    if ! python3 "$(read_exclusion_python)/exclusions.py" remove "${EXCLUSION_FILE}" "$1" 2>"${err}"; then
        report_exclusion_error "$(cat "${err}")"
        rm -f "${err}"
        exit 1
    fi
    rm -f "${err}"
    printf '%s\n' "$(get_text log.exclusion-removed "$1")"
    run_exclusion_apply
}

run_exclusion_review() {
    local days=90
    if [[ "${1:-}" == "--older-than" ]]; then
        days="${2:-}"
        days="${days%d}"
        if [[ ! "${days}" =~ ^[0-9]+$ ]]; then
            show_usage
            exit 1
        fi
    elif [[ -n "${1:-}" ]]; then
        show_usage
        exit 1
    fi
    python3 "$(read_exclusion_python)/exclusions.py" review "${EXCLUSION_FILE}" "$(date +%F)" "${days}"
}

run_exclusion_command() {
    case "${1:-}" in
        add)
            shift
            run_exclusion_add "$@"
            ;;
        list)
            shift
            run_exclusion_list "$@"
            ;;
        del)
            shift
            run_exclusion_remove "$@"
            ;;
        apply) run_exclusion_apply ;;
        review)
            shift
            run_exclusion_review "$@"
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

set -euo pipefail

prepare_exclusion
run_exclusion_command "$@"
