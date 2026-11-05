#!/usr/bin/env bash
# =============================================================================
# File       : system/collect-logs.sh
# Updated at : 2026-11-05
# Creator    : palarchsys
# =============================================================================

INSTALL_DIRECTORY="${1:-}"
if [[ -z "$INSTALL_DIRECTORY" ]]; then
    INSTALL_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
fi
export INSTALL_DIRECTORY

# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/core/lib.sh"
# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/config/global.conf"

require_root
collect_manual
