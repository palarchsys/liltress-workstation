#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/configure.sh
# Updated at : 2026-11-14
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
# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/service/vpn/lib.sh"
# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/service/vpn/state.sh"
require_root

render_vpn_unit() {
    local name="$1" src dest
    src="$(locate_config_file "vpn/${name}")" || log_error "${INSTALL_WATCHER}" "vpn.profile.invalid" "${name}"
    dest="/etc/systemd/system/${name}"
    if [[ -f "${dest}" ]]; then
        copy_backup "${dest}"
    fi
    sed "s|@ROOT@|${INSTALL_DIRECTORY}|g" "${src}" > "${dest}"
    chmod 644 "${dest}"
}

home="$(get_vpn_home)"
install -d -m 755 "${home}"
install -d -m 700 "${home}/wireguard" "${home}/openvpn"
write_vpn_state
install -m 644 "$(locate_config_file vpn/vpn.conf)" "${home}/vpn.conf"
if [[ ! -f "${home}/bypass.cidrs" ]]; then
    install -m 644 "$(locate_config_file vpn/bypass.cidrs)" "${home}/bypass.cidrs"
fi
install -d -m 755 /etc/iproute2/rt_tables.d
rt_file="/etc/iproute2/rt_tables.d/liltress-vpn.conf"
if [[ -f "${rt_file}" ]]; then
    copy_backup "${rt_file}"
fi
printf '17820 w_vpn\n17821 w_direct\n' > "${rt_file}"
chmod 644 "${rt_file}"
disp_dir="/etc/NetworkManager/dispatcher.d"
disp_dest="${disp_dir}/10-liltress-workstation-vpn"
install -d -m 755 "${disp_dir}"
if [[ -f "${disp_dest}" ]]; then
    copy_backup "${disp_dest}"
fi
sed "s|@ROOT@|${INSTALL_DIRECTORY}|g" "${INSTALL_DIRECTORY}/service/vpn/nm-dispatcher.sh" > "${disp_dest}"
chmod 755 "${disp_dest}"
render_vpn_unit w-vpn-killswitch.service
render_vpn_unit w-vpn.service
render_vpn_unit w-vpn-watch.service
render_vpn_unit w-vpn-watch.timer
run_silent       "${INSTALL_WATCHER}" "vpn.install.fail" systemctl daemon-reload
load_vpn_settings
apply_vpn_systemd
log_success      "${INSTALL_WATCHER}" "vpn.configure.ok"
