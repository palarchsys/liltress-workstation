#!/usr/bin/env bash
# =============================================================================
# File       : core/log/display.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Load the color, step, and message scripts.
# -----------------------------------------------------------------------------


display_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${display_directory}/color.sh"
# shellcheck disable=SC1091
source "${display_directory}/step.sh"
# shellcheck disable=SC1091
source "${display_directory}/emit.sh"
unset display_directory
