#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/egress.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Build the body of one egress alert.
# -----------------------------------------------------------------------------


# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../boot/python.sh"

render_egress_body() {
    local kernel="$1"
    local audit="${2:-}"
    EGRESS_AUDIT_FILE="${audit}" python3 "$(locate_python_directory)/egress-body.py" core "${kernel}"
}
