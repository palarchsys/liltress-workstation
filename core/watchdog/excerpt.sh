#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/excerpt.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Keep a short redacted piece of one journal.
# -----------------------------------------------------------------------------


source_python_boot() {
    local dir hops
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    hops=0
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        if [[ -f "${dir}/core/boot/python.sh" ]]; then
            # shellcheck disable=SC1090
            source "${dir}/core/boot/python.sh"
            return 0
        fi
        if [[ -f "${dir}/share/core/boot/python.sh" ]]; then
            # shellcheck disable=SC1090
            source "${dir}/share/core/boot/python.sh"
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

source_python_boot

get_alert_excerpt() {
    load_text "${LANGUAGE:-en}"
    TEXT_EXCERPT_MORE="$(get_text alert.excerpt.more)" \
    TEXT_EXCERPT_ATTR="$(get_text alert.excerpt.attr)" \
    TEXT_REDACTED="$(get_text mail.redacted)" \
    TEXT_REDACTED_KEY="$(get_text mail.redacted-key)" \
        python3 "$(locate_python_dir)/alert-excerpt.py" "${1:-}"
}
