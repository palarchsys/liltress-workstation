#!/usr/bin/env bash
# =============================================================================
# File       : service/tailscale/configure.sh
# Updated at : 2026-11-21
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Connect Tailscale, then remove SSH entry outside that link.
# -----------------------------------------------------------------------------


INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
source "${INSTALL_DIRECTORY}/service/tailscale/common.sh"
require_root

run_tailscale_session
ss -lnt | grep -q ":${SSH_PORT}[[:space:]]" || log_error "${INSTALL_WATCHER}" "configure.tailscale.bad"
clear_public_ssh
