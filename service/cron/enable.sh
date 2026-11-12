#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/enable.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

# -----------------------------------------------------------------------------
# Purpose    : Enable the timers before the reference databases are built.
# Note       : systemctl enable creates the timers.target.wants links and does not start a watchdog.
# -----------------------------------------------------------------------------

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${here}/arm.sh" "${1:-BASH}" "${2:-}" "${3:-}" enable
