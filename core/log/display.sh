#!/usr/bin/env bash
# =============================================================================
# File       : core/log/display.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

display_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${display_dir}/color.sh"
# shellcheck disable=SC1091
source "${display_dir}/step.sh"
# shellcheck disable=SC1091
source "${display_dir}/emit.sh"
unset display_dir
