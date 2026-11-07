#!/usr/bin/env bash
# =============================================================================
# File       : core/log.sh
# Updated at : 2026-11-07
# Creator    : palarchsys
# =============================================================================

_log_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
_log_load() {
    local name="$1"
    local candidate=""
    for candidate in \
        "${_log_here}/${name}" \
        "${INSTALL_DIRECTORY:-}/core/${name}" \
        "${INSTALL_DIRECTORY:-}/src/core/${name}" \
        "${PRODUCT_ROOT:-}/core/${name}" \
        "${PRODUCT_ROOT:-}/../share/core/${name}"
    do
        if [[ -n "${candidate}" && -f "${candidate}" ]]; then
            # shellcheck disable=SC1090
            source "${candidate}"
            return 0
        fi
    done
    printf 'core/%s not found beside %s\n' "${name}" "${_log_here}" >&2
    exit 1
}
# shellcheck disable=SC1091
_log_load text.sh
# shellcheck disable=SC1091
_log_load display.sh
# shellcheck disable=SC1091
_log_load journal.sh
unset -f _log_load
unset _log_here

load_product_text

if [[ -n "${STEP_LABEL:-}" && "${STEP_TREE:-0}" != "1" && "${INSTALL_WATCHER:-BASH}" != "GO" ]]; then
    open_step_tree "${STEP_LABEL}"
    note_bash success "$(get_text log.execution)"
    unset STEP_LABEL
    trap 'close_step_tree' EXIT
fi
