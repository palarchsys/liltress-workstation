#!/usr/bin/env bash
# =============================================================================
# File       : system/purge.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY
G_INSTALL_DIRECTORY="${INSTALL_DIRECTORY}"
export G_INSTALL_DIRECTORY

# shellcheck disable=SC2034
# shellcheck disable=SC2155
readonly DIR_SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${G_INSTALL_DIRECTORY}/core/lib.sh"
source "${G_INSTALL_DIRECTORY}/config/global.conf"

require_root

remove_cups() {

    local p unit
    local -a cups_pkgs=()
    log_subtitle "${INSTALL_WATCHER}" "log.cups"
    for p in cups cups-daemon cups-browsed cups-core-drivers cups-server-common cups-filters; do
        if dpkg-query -W -f '${Status}\n' "${p}" 2>/dev/null | grep -q 'install ok'; then
            cups_pkgs+=("${p}")
        fi
    done
    if dpkg-statoverride --list /etc/cups/cupsd.conf >/dev/null 2>&1; then
        dpkg-statoverride --remove /etc/cups/cupsd.conf >/dev/null 2>&1 || true
    fi
    if [[ ${#cups_pkgs[@]} -gt 0 ]]; then
        log_info "${INSTALL_WATCHER}" "log.purge-of-cups" "${cups_pkgs[*]}"
        for unit in cups.socket cups.path cups-browsed.socket cups-browsed.service cups.service; do
            timeout 20 systemctl disable --now "${unit}" >/dev/null 2>&1 || true
            timeout 20 systemctl stop "${unit}" >/dev/null 2>&1 || true
            systemctl kill "${unit}" >/dev/null 2>&1 || true
        done
        run_silent_apt "${INSTALL_WATCHER}" "purge -y ${cups_pkgs[*]}" "install.purge.error"
        log_success "${INSTALL_WATCHER}" "log.cups-purged"
    else
        log_info "${INSTALL_WATCHER}" "log.check-of-cups"
        log_success "${INSTALL_WATCHER}" "log.cups-absent"
    fi
}

remove_removed_config_package() {

    log_subtitle "${INSTALL_WATCHER}" "log.purge-of-the-packages-rc-lynis-pkgs-7346"
    log_info "${INSTALL_WATCHER}" "log.check-of-the-packages-rc"
    mapfile -t rc_all < <(dpkg -l 2>/dev/null | awk '/^rc/{print $2}')
    rc_pkgs=()
    local p
    for p in "${rc_all[@]}"; do
        case "${p}" in
            grub-pc|grub-pc-bin|grub-gfxpayload-lists) log_info "${INSTALL_WATCHER}" "log.rc-kept-boot" "${p}";;
            *) rc_pkgs+=("${p}") ;;
        esac
    done
    if [[ ${#rc_pkgs[@]} -gt 0 ]]; then
        log_info "${INSTALL_WATCHER}" "log.purge-of-the-packages-rc-2" "${rc_pkgs[*]}"
        run_silent_apt "${INSTALL_WATCHER}" "purge -y ${rc_pkgs[*]}" "install.purge.error"
        log_success "${INSTALL_WATCHER}" "log.packages-rc-purged" "${#rc_pkgs[@]}"
    else
        log_success "${INSTALL_WATCHER}" "log.no-package-rc-to-purge"
    fi
}

if [[ "${G_PURGE_REMOVED_CONFIG_ONLY:-0}" == "1" ]]; then
    remove_removed_config_package
    exit 0
fi

if [[ "${G_REAPPLY_LOCKS:-0}" == "1" ]]; then

    log_subtitle "${INSTALL_WATCHER}" "log.reapplication-of-the-deactivations"
    log_info "${INSTALL_WATCHER}" "log.the-last-upgrade-can-re-enable-systemd-coredump"
else

remove_cups

remove_removed_config_package

log_success "${INSTALL_WATCHER}" "log.purge-workstation-finished"

fi

log_info "${INSTALL_WATCHER}" "log.masking-of-systemd-coredump"
run_optional "${INSTALL_WATCHER}" "install.purge.error" systemctl mask systemd-coredump.socket
log_success "${INSTALL_WATCHER}" "log.systemd-coredump-masked"
