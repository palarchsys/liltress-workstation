#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/arm-onaccess.sh
# Updated at : 2026-11-17
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Start the on-access unit that install already enabled.
# Note       : Paths stay in the scanner configuration.
# -----------------------------------------------------------------------------


arm_onaccess() {
    local unit=""
    command -v systemctl >/dev/null 2>&1 || return 0
    for unit in clamav-clamonacc.service clamonacc.service; do
        if systemctl cat "${unit}" >/dev/null 2>&1; then
            systemctl start "${unit}" || true
            return 0
        fi
    done
}

set -euo pipefail
arm_onaccess
exit 0
