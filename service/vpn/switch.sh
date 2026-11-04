#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/switch.sh
# Updated at : 2026-11-04
# Creator    : palarchsys
# =============================================================================

fail_vpn_switch() {
    local name="$1" proto endpoint
    proto="$(get_vpn_meta "${name}" proto 2>/dev/null || true)"
    endpoint="$(get_vpn_meta "${name}" endpoint4 2>/dev/null || true)"
    [[ -n "${endpoint}" ]] || endpoint="$(get_vpn_meta "${name}" endpoint6 2>/dev/null || true)"
    remove_vpn_iface "${name}"
    clear_vpn_tunnel_routes
    apply_vpn_nft "${name}" 0 || true
    clear_vpn_active
    send_vpn_alert "${name}" "${proto}" "${endpoint%% *}" "switch"
    log_error "${INSTALL_WATCHER:-BASH}" "vpn.switch.fail" "${name}"
}

run_vpn_switch() {
    local name="$1" old raised=0
    load_vpn_settings
    check_vpn_name "${name}" || log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.bad-name" "${name}"
    [[ -f "$(get_vpn_profile_dir "${name}")/runtime" ]] || log_error "${INSTALL_WATCHER:-BASH}" "vpn.profile.invalid" "${name}"
    if check_vpn_encrypted "${name}" && ! check_vpn_passphrase; then
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.up.agent" "${name}"
    fi
    old="$(get_vpn_active 2>/dev/null || true)"
    if [[ "${old}" == "${name}" ]] && check_vpn_tunnel "${name}"; then
        log_success "${INSTALL_WATCHER:-BASH}" "vpn.up.same" "${name}"
        return 0
    fi
    apply_vpn_nft "${name}" 0 || log_error "${INSTALL_WATCHER:-BASH}" "vpn.profile.invalid" "${name}"
    clear_vpn_conntrack "${name}"
    if [[ -n "${old}" && "${old}" != "${name}" ]]; then
        remove_vpn_iface "${old}"
    fi
    clear_vpn_tunnel_routes
    apply_vpn_bypass_routes
    apply_vpn_endpoint_routes "${name}"
    apply_vpn_profile "${name}" || raised=$?
    if (( raised == 2 )); then
        apply_vpn_nft "${name}" 0 || true
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.up.agent" "${name}"
    fi
    if (( raised != 0 )); then
        fail_vpn_switch "${name}"
    fi
    apply_vpn_tunnel_routes "${name}" || fail_vpn_switch "${name}"
    apply_vpn_nft "${name}" 1 || fail_vpn_switch "${name}"
    if ! wait_vpn_handshake "${name}"; then
        fail_vpn_switch "${name}"
    fi
    refresh_vpn_ipv6 "${name}"
    apply_vpn_tunnel_routes "${name}" || fail_vpn_switch "${name}"
    apply_vpn_nft "${name}" 1 || fail_vpn_switch "${name}"
    set_vpn_active "${name}"
    log_success "${INSTALL_WATCHER:-BASH}" "vpn.switch.ok" "${name}"
}
