#!/usr/bin/env bash
# =============================================================================
# File       : core/log/log.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

if ! declare -F source_core >/dev/null 2>&1; then
    # shellcheck disable=SC1091
    source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../boot" && pwd)/bootstrap.sh"
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
