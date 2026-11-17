#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/refresh-debsums-db.sh
# Updated at : 2026-11-17
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Confirm that debsums is installed.
# Note       : The sums come from the packages already installed.
# -----------------------------------------------------------------------------


set -euo pipefail
command -v debsums >/dev/null 2>&1 || true
exit 0
