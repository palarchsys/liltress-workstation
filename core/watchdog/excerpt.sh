#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/excerpt.sh
# Updated at : 2026-11-11
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


get_alert_excerpt() {
    load_text "${LANGUAGE:-en}"
    TEXT_EXCERPT_MORE="$(get_text alert.excerpt.more)" \
    TEXT_EXCERPT_ATTR="$(get_text alert.excerpt.attr)" \
    TEXT_REDACTED="$(get_text mail.redacted)" \
    TEXT_REDACTED_KEY="$(get_text mail.redacted-key)" \
    python3 "$(locate_python_dir)/alert-excerpt.py" "${1:-}"
}
