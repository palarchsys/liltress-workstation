#!/usr/bin/env bash
# =============================================================================
# File       : core/log/log.sh
# Updated at : 2026-11-13
# Creator    : palarchsys
# =============================================================================

load_log_bootstrap() {
    local log_dir="" bootstrap_file="" bootstrap_candidate="" hops=0
    log_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "${log_dir}/../boot/bootstrap.sh" ]]; then
        bootstrap_file="${log_dir}/../boot/bootstrap.sh"
    fi
    bootstrap_candidate="${log_dir}"
    while [[ -z "${bootstrap_file}" && -n "${bootstrap_candidate}" && "${bootstrap_candidate}" != "/" && "${hops}" -lt 16 ]]; do
        if [[ -f "${bootstrap_candidate}/core/boot/bootstrap.sh" ]]; then
            bootstrap_file="${bootstrap_candidate}/core/boot/bootstrap.sh"
            break
        fi
        if [[ -f "${bootstrap_candidate}/share/core/boot/bootstrap.sh" ]]; then
            bootstrap_file="${bootstrap_candidate}/share/core/boot/bootstrap.sh"
            break
        fi
        bootstrap_candidate="$(dirname -- "${bootstrap_candidate}")"
        hops=$((hops + 1))
    done
    if [[ -z "${bootstrap_file}" ]]; then
        printf 'bootstrap.sh introuvable depuis %s\n' "${log_dir}" >&2
        exit 1
    fi
    # shellcheck disable=SC1090
    source "${bootstrap_file}"
}

if ! declare -F source_core >/dev/null 2>&1; then
    load_log_bootstrap
fi
source_core text/text.sh
source_core log/display.sh
source_core log/journal.sh

load_product_text

if [[ -n "${STEP_LABEL:-}" && "${STEP_TREE:-0}" != "1" && "${INSTALL_WATCHER:-BASH}" != "GO" ]]; then
    open_step_tree "${STEP_LABEL}"
    note_bash success "$(get_text log.execution)"
    unset STEP_LABEL
    trap 'close_step_tree' EXIT
fi
