#!/usr/bin/env bash
# =============================================================================
# File       : service/lynis/configure.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY
G_INSTALL_DIRECTORY="${INSTALL_DIRECTORY}"
export G_INSTALL_DIRECTORY

source "${G_INSTALL_DIRECTORY}/core/lib.sh"
source "${G_INSTALL_DIRECTORY}/config/global.conf"
require_root
log_info         "${INSTALL_WATCHER}" "configure.install-of-the-profile-lynis-workstation-of-work"
mkdir -p /etc/lynis
tee /etc/lynis/custom.prf > /dev/null << 'EOF'
machine-role=workstation
skip-test=HRDN-7222
skip-test=FILE-6310
skip-test=FILE-6372
skip-test=FILE-6374
skip-test=BOOT-5122
skip-test=KRNL-6000:kernel.modules_disabled
skip-test=KRNL-6000:net.ipv4.conf.all.forwarding
skip-test=KRNL-6000:net.ipv4.ip_forward
skip-test=KRNL-6000:net.ipv4.conf.all.rp_filter
skip-test=KRNL-6000:net.ipv4.conf.default.rp_filter
skip-test=KRNL-6000:kernel.unprivileged_userns_clone
skip-test=USB-1000
skip-test=AUTH-9282
skip-test=AUTH-9286
skip-test=SSH-7408
skip-test=TOOL-5002
skip-test=LOGG-2154
EOF
chmod 644 /etc/lynis/custom.prf
log_success      "${INSTALL_WATCHER}" "configure.custom-prf-lynis-installed"
