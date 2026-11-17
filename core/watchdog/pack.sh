#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/pack.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Write the zip a real detection attaches to the mail.
# Note       : The archive keeps only the logs of this cycle. Later cycles stay out.
# -----------------------------------------------------------------------------


# The caller owns shown_python and reads it after this call.
show_python_directory() {
    local candidate="$1"
    shown_python=0
    [[ -n "${candidate}" && -d "${candidate}" ]] || return 0
    (cd -- "${candidate}" && pwd -P)
    shown_python=1
    return 0
}

# The shared directory is printed as given, without resolving links.
show_share_python() {
    local dir="$1"
    shown_python=0
    if [[ ! -d "${dir}/share/python" ]]; then
        return 0
    fi
    printf '%s\n' "${dir}/share/python"
    shown_python=1
    return 0
}

locate_python_dir() {
    local dir="" hops=0 candidate="" shown_python=0
    for candidate in \
        "${CONFIG_BASE_DIRECTORY:-}/python" \
        "${BASE:-}/python" \
        "${INSTALL_DIRECTORY:-}/python" \
        "${INSTALL_DIRECTORY:-}/../share/python"; do
        show_python_directory "${candidate}"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
    done
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        show_share_python "${dir}"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
        show_python_directory "${dir}/python"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

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
