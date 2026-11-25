#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/pack.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Write the zip a real detection attaches to the mail.
# Note       : The archive keeps only the logs of this cycle. Later cycles stay out.
# -----------------------------------------------------------------------------


# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../boot/python.sh"

write_watchdog_pack() {
    local phase="$1"
    local state_directory="$2"
    local log_directory="$3"
    local base stamp dest excludes
    base="$(get_product_base)"
    stamp="$(date '+%Y%m%d-%H%M%S')"
    mkdir -p -- "${base}/log"
    dest="${base}/log/alert-${phase}-${stamp}.zip"
    excludes="$(read_watchdog_exclude | awk 'NR > 1 { printf ":" } { printf "%s", $0 }')"
    WATCHDOG_EXCLUDES="${excludes}" \
        python3 "$(locate_python_directory)/alert-pack.py" "${phase}" "${state_directory}" "${log_directory}" "${dest}"
    chmod 600 "${dest}" 2>/dev/null || true
    printf '%s\n' "${dest}"
}
