#!/usr/bin/env bash
# =============================================================================
# File       : system/purge/cups.sh
# Updated at : 2026-11-05
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

local_p=""
local_unit=""
cups_pkgs=()
log_subtitle "${INSTALL_WATCHER}" "log.cups"
for local_p in cups cups-daemon cups-browsed cups-core-drivers cups-server-common cups-filters; do
    if dpkg-query -W -f '${Status}\n' "${local_p}" 2>/dev/null | grep -q 'install ok'; then
        cups_pkgs+=("${local_p}")
    fi
done
if dpkg-statoverride --list /etc/cups/cupsd.conf >/dev/null 2>&1; then
    dpkg-statoverride --remove /etc/cups/cupsd.conf >/dev/null 2>&1 || true
fi
if [[ ${#cups_pkgs[@]} -gt 0 ]]; then
    log_info "${INSTALL_WATCHER}" "log.purge-of-cups" "${cups_pkgs[*]}"
    for local_unit in cups.socket cups.path cups-browsed.socket cups-browsed.service cups.service; do
        timeout 20 systemctl disable --now "${local_unit}" >/dev/null 2>&1 || true
        timeout 20 systemctl stop "${local_unit}" >/dev/null 2>&1 || true
        systemctl kill "${local_unit}" >/dev/null 2>&1 || true
    done
    run_silent_apt "${INSTALL_WATCHER}" "purge -y ${cups_pkgs[*]}" "install.purge.error"
    log_success "${INSTALL_WATCHER}" "log.cups-purged"
else
    log_info "${INSTALL_WATCHER}" "log.check-of-cups"
    log_success "${INSTALL_WATCHER}" "log.cups-absent"
fi
