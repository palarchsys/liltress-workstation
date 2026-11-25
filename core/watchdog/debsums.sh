#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/debsums.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Reset one debsums journal after a package is installed again.
# -----------------------------------------------------------------------------


# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../boot/python.sh"

set_rkhunter_note() {
    local base
    base="$(get_product_base)"
    NOTE="$(get_text alert.note.rkhunter)"
    NOTE_CMD="sudo bash ${base}/service/rkhunter/refresh-db.sh"
}

reset_debsums_log() {
    local log="$1"
    local summary=""
    [[ -n "${log}" && -s "${log}" ]] || return 0
    summary="$(
        python3 "$(locate_python_directory)/debsums-reset.py" "${log}" || true
    )"
    printf '%s' "${summary}"
}
