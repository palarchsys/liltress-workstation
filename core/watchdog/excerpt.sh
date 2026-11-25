#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/excerpt.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Keep a short redacted piece of one journal.
# -----------------------------------------------------------------------------


# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../boot/python.sh"

get_alert_excerpt() {
    load_text "${LANGUAGE:-en}"
    TEXT_EXCERPT_MORE="$(get_text alert.excerpt.more)" \
    TEXT_EXCERPT_ATTR="$(get_text alert.excerpt.attr)" \
    TEXT_REDACTED="$(get_text mail.redacted)" \
    TEXT_REDACTED_KEY="$(get_text mail.redacted-key)" \
        python3 "$(locate_python_directory)/alert-excerpt.py" "${1:-}"
}
