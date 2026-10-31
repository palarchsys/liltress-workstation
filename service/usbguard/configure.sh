#!/usr/bin/env bash
# =============================================================================
# File       : service/usbguard/configure.sh
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
get_current_user

log_subtitle     "${INSTALL_WATCHER}" "configure.policy-usbguard"

log_info         "${INSTALL_WATCHER}" "configure.write-of-the-rules-usbguard"
install -d -m 750 /etc/usbguard /etc/usbguard/IPCAccessControl.d
rules=/etc/usbguard/rules.conf
: > "${rules}"
if command -v usbguard >/dev/null 2>&1; then
    usbguard generate-policy > "${rules}.gen" 2>/dev/null || true
    if [[ -s "${rules}.gen" ]]; then
        cat "${rules}.gen" > "${rules}"
    fi
    rm -f "${rules}.gen"
fi
grep -v '^#' "$(locate_config_file usbguard/hid.rules)" >> "${rules}"
chmod 600 "${rules}"
if ! grep -qF 'allow with-interface equals { 03:*:* }' "${rules}"; then
    log_warn         "${INSTALL_WATCHER}" "configure.usbguard-left-stopped-the-rule-clavier-is-missin"
    run_optional     "${INSTALL_WATCHER}" "configure.usbguard.error" systemctl disable --now usbguard
    exit 0
fi

daemon_conf=/etc/usbguard/usbguard-daemon.conf
if [[ ! -f "${daemon_conf}" ]]; then
    install -m 600 /dev/null "${daemon_conf}"
fi

set_usb_rule() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "${daemon_conf}"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "${daemon_conf}"
    else
        printf '%s=%s\n' "${key}" "${value}" >> "${daemon_conf}"
    fi
}

load_usb_rule() {
    local line key value
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" || "${line}" == \#* ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        set_usb_rule "${key}" "${value}"
    done < "$(locate_config_file usbguard/daemon.conf)"
}
load_usb_rule
set_usb_rule IPCAllowedUsers "root ${CURRENT_USER}"
chmod 600 "${daemon_conf}"

ipc="/etc/usbguard/IPCAccessControl.d/${CURRENT_USER}"
grep -v '^#' "$(locate_config_file usbguard/ipc.acl)" > "${ipc}"
chmod 600 "${ipc}"

log_info         "${INSTALL_WATCHER}" "configure.activation-of-usbguard"
if systemctl enable --now usbguard >/dev/null 2>&1; then
    log_success      "${INSTALL_WATCHER}" "configure.active-usbguard-appareils-pr-sents-and-hid-autor"
else
    log_warn         "${INSTALL_WATCHER}" "configure.usbguard-did-not-started-service-left-stopped"
    run_optional     "${INSTALL_WATCHER}" "configure.usbguard.error" systemctl disable --now usbguard
fi
