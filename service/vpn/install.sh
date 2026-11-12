#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/install.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY
if [[ -z "${PRODUCT_ROOT:-}" ]]; then
    PRODUCT_ROOT="${INSTALL_DIRECTORY}"
    export PRODUCT_ROOT
fi

# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info         "${INSTALL_WATCHER}" "vpn.install.title"
run_silent_apt   "${INSTALL_WATCHER}" "install -y wireguard-tools openvpn conntrack" "vpn.install.fail"
if [[ ! -d /sys/module/wireguard ]]; then
    modprobe wireguard >/dev/null 2>&1 || log_error "${INSTALL_WATCHER}" "vpn.module.missing"
fi
if [[ ! -d /sys/module/wireguard ]]; then
    log_error "${INSTALL_WATCHER}" "vpn.module.missing"
fi
log_success      "${INSTALL_WATCHER}" "vpn.install.ok"
