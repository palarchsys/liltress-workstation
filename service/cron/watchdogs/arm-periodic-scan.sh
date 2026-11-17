#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/arm-periodic-scan.sh
# Updated at : 2026-11-17
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Arm the periodic timer without running its body again.
# Note       : The next pass follows the timer, one hour after this arm.
# -----------------------------------------------------------------------------


arm_periodic_scan() {
    local unit=""
    command -v systemctl >/dev/null 2>&1 || return 0
    for unit in w-periodic-scan.timer s-periodic-scan.timer; do
        if systemctl cat "${unit}" >/dev/null 2>&1; then
            systemctl enable --now "${unit}" || true
            return 0
        fi
    done
}

set -euo pipefail
arm_periodic_scan
exit 0
