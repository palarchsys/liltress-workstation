#!/usr/bin/env bash
# =============================================================================
# File       : system/collect-logs.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

G_INSTALL_DIRECTORY="${1:-}"
if [[ -z "$G_INSTALL_DIRECTORY" ]]; then
    G_INSTALL_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
fi
export G_INSTALL_DIRECTORY

# shellcheck disable=SC1091
source "${G_INSTALL_DIRECTORY}/core/lib.sh"
# shellcheck disable=SC1091
source "${G_INSTALL_DIRECTORY}/config/global.conf"

require_root
collect_manual
