#!/usr/bin/env bash
# =============================================================================
# File       : system/purge/rc.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info "${INSTALL_WATCHER}" "log.check-of-the-packages-rc"
mapfile -t rc_all < <(dpkg -l 2>/dev/null | awk '/^rc/{print $2}')
rc_pkgs=()
local_p=""
for local_p in "${rc_all[@]}"; do
    case "${local_p}" in
        grub-pc|grub-pc-bin|grub-gfxpayload-lists) log_info "${INSTALL_WATCHER}" "log.rc-kept-boot" "${local_p}";;
        *) rc_pkgs+=("${local_p}") ;;
    esac
done
if [[ ${#rc_pkgs[@]} -gt 0 ]]; then
    log_info "${INSTALL_WATCHER}" "log.purge-of-the-packages-rc-2" "${rc_pkgs[*]}"
    run_silent_apt "${INSTALL_WATCHER}" "purge -y ${rc_pkgs[*]}" "install.purge.error"
    log_success "${INSTALL_WATCHER}" "log.packages-rc-purged" "${#rc_pkgs[@]}"
else
    log_success "${INSTALL_WATCHER}" "log.no-package-rc-to-purge"
fi
