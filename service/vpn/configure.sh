#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/configure.sh
# Updated at : 2026-11-04
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY
G_INSTALL_DIRECTORY="${INSTALL_DIRECTORY}"
export G_INSTALL_DIRECTORY
if [[ -z "${G_PRODUCT_ROOT:-}" ]]; then
    G_PRODUCT_ROOT="${INSTALL_DIRECTORY}"
    export G_PRODUCT_ROOT
fi

# shellcheck disable=SC1091
source "${G_INSTALL_DIRECTORY}/core/lib.sh"
# shellcheck disable=SC1091
source "${G_INSTALL_DIRECTORY}/config/global.conf"
# shellcheck disable=SC1091
source "${G_INSTALL_DIRECTORY}/service/vpn/lib.sh"
require_root

render_vpn_unit() {
    local name="$1" src dest
    src="$(locate_config_file "vpn/${name}")" || log_error "${INSTALL_WATCHER}" "vpn.profile.invalid" "${name}"
    dest="/etc/systemd/system/${name}"
    if [[ -f "${dest}" ]]; then
        copy_backup "${dest}"
    fi
    sed "s|@ROOT@|${G_INSTALL_DIRECTORY}|g" "${src}" > "${dest}"
    chmod 644 "${dest}"
}

log_subtitle     "${INSTALL_WATCHER}" "vpn.install.title"
home="$(get_vpn_home)"
install -d -m 755 "${home}"
install -d -m 700 "${home}/wireguard" "${home}/openvpn"
install -m 644 "$(locate_config_file vpn/vpn.conf)" "${home}/vpn.conf"
if [[ ! -f "${home}/bypass.cidrs" ]]; then
    install -m 644 "$(locate_config_file vpn/bypass.cidrs)" "${home}/bypass.cidrs"
fi
install -d -m 755 /etc/iproute2/rt_tables.d
rt_file="/etc/iproute2/rt_tables.d/liltress-vpn.conf"
if [[ -f "${rt_file}" ]]; then
    copy_backup "${rt_file}"
fi
printf '17820 w_vpn\n' > "${rt_file}"
chmod 644 "${rt_file}"
render_vpn_unit w-vpn-killswitch.service
render_vpn_unit w-vpn.service
run_silent       "${INSTALL_WATCHER}" "vpn.install.fail" systemctl daemon-reload
load_vpn_settings
apply_vpn_systemd
log_success      "${INSTALL_WATCHER}" "vpn.configure.ok"
