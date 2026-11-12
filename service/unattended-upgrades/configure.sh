#!/usr/bin/env bash
# =============================================================================
# File       : service/unattended-upgrades/configure.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info         "${INSTALL_WATCHER}" "configure.configuration-of-unattended-upgrades-security-on"
ensure_directory /etc/apt/apt.conf.d 755

grep -v '^#' "$(locate_config_file unattended-upgrades/20auto-upgrades)" > /etc/apt/apt.conf.d/20auto-upgrades
grep -v '^#' "$(locate_config_file unattended-upgrades/51liltress-workstation)" > /etc/apt/apt.conf.d/51liltress-workstation
chmod 644 /etc/apt/apt.conf.d/20auto-upgrades /etc/apt/apt.conf.d/51liltress-workstation

run_silent       "${INSTALL_WATCHER}" "configure.unattended-upgrades.error" systemctl enable --now unattended-upgrades
log_success      "${INSTALL_WATCHER}" "configure.unattended-upgrades-configured-security-only-reb"
