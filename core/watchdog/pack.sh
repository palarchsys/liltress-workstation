#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/pack.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================


locate_python_dir() {
    local dir hops=0
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        if [[ -d "${dir}/share/python" ]]; then
            printf '%s\n' "${dir}/share/python"
            return 0
        fi
        if [[ -d "${dir}/python" ]]; then
            printf '%s\n' "${dir}/python"
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

# -----------------------------------------------------------------------------
# Purpose    : Write the zip a real watchdog detection attaches to the mail.
# Note       : The archive keeps only the logs of this pass. Later passes stay out.
# -----------------------------------------------------------------------------

write_watchdog_pack() {
    local phase="$1"
    local state_dir="$2"
    local log_dir="$3"
    local base stamp dest excludes
    base="$(get_product_base)"
    stamp="$(date '+%Y%m%d-%H%M%S')"
    mkdir -p -- "${base}/log"
    dest="${base}/log/alert-${phase}-${stamp}.zip"
    excludes="$(read_watchdog_exclude | awk 'NR > 1 { printf ":" } { printf "%s", $0 }')"
    WATCHDOG_EXCLUDES="${excludes}" \
    python3 "$(locate_python_dir)/alert-pack.py" "${phase}" "${state_dir}" "${log_dir}" "${dest}"
    chmod 600 "${dest}" 2>/dev/null || true
    printf '%s\n' "${dest}"
}
