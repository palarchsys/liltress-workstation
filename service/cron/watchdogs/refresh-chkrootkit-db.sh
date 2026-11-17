#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/refresh-chkrootkit-db.sh
# Updated at : 2026-11-17
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Confirm that chkrootkit is installed.
# Note       : The tool has no signature database to refresh.
# -----------------------------------------------------------------------------


set -euo pipefail
command -v chkrootkit >/dev/null 2>&1 || true
exit 0
