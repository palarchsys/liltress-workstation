#!/usr/bin/env bash
# =============================================================================
# File       : service/tailscale/configure.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Connect Tailscale, then remove SSH entry outside that link.
# Note       : UFW names tailscale0 only after that link exists.
# -----------------------------------------------------------------------------


INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
source "${INSTALL_DIRECTORY}/service/tailscale/common.sh"

# tailscaled alone does not create the interface. UFW rejects a missing name.
set_tailscale_ufw() {
    run_silent "${INSTALL_WATCHER}" "configure.ufw.error" ufw allow in on tailscale0 to any port "${SSH_PORT}" proto tcp comment "OpenSSH via Tailscale only"
    run_silent "${INSTALL_WATCHER}" "configure.ufw.error" ufw deny in on tailscale0 comment "Tailscale ingress is SSH only"
    run_silent "${INSTALL_WATCHER}" "configure.ufw.error" ufw allow out on tailscale0 to any port "${SSH_PORT}" proto tcp comment "Workstation SSH toward tailnet"
    run_silent "${INSTALL_WATCHER}" "configure.ufw.error" ufw route deny out on tailscale0 comment "No route out via Tailscale"
    run_silent "${INSTALL_WATCHER}" "configure.ufw.error" ufw route deny in on tailscale0 comment "No route in via Tailscale"
}
require_root

run_tailscale_session
set_tailscale_ufw
ss -lnt | grep -q ":${SSH_PORT}[[:space:]]" || log_error "${INSTALL_WATCHER}" "configure.tailscale.bad"
clear_public_ssh
