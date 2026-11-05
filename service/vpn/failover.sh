#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/failover.sh
# Updated at : 2026-11-05
# Creator    : palarchsys
# =============================================================================

arm_vpn_lockdown() {
    local name
    load_vpn_settings
    name="$(get_vpn_active 2>/dev/null || true)"
    if [[ -n "${name}" ]]; then
        remove_vpn_iface "${name}"
    fi
    ip link del "${W_VPN_IFACE_WG}" >/dev/null 2>&1 || true
    ip link del "${W_VPN_IFACE_OVPN}" >/dev/null 2>&1 || true
    ip link del wgl-probe >/dev/null 2>&1 || true
    ip link del tun-probe >/dev/null 2>&1 || true
    clear_vpn_tunnel_routes || true
    clear_vpn_active
    apply_vpn_nft "" 0 || true
    apply_vpn_bypass_routes || true
}

run_vpn_profile() {
    local name="$1" limit="${2:-${W_VPN_HANDSHAKE_TIMEOUT}}"
    local saved raised=0
    saved="${W_VPN_HANDSHAKE_TIMEOUT}"
    W_VPN_HANDSHAKE_TIMEOUT="${limit}"
    if check_vpn_encrypted "${name}" && ! check_vpn_passphrase; then
        W_VPN_HANDSHAKE_TIMEOUT="${saved}"
        return 2
    fi
    if ! arm_vpn_closed "${name}"; then
        W_VPN_HANDSHAKE_TIMEOUT="${saved}"
        return 1
    fi
    apply_vpn_profile "${name}" || raised=$?
    if (( raised != 0 )); then
        remove_vpn_iface "${name}"
        W_VPN_HANDSHAKE_TIMEOUT="${saved}"
        return "${raised}"
    fi
    if ! apply_vpn_tunnel_routes "${name}"; then
        remove_vpn_iface "${name}"
        W_VPN_HANDSHAKE_TIMEOUT="${saved}"
        return 1
    fi
    if ! apply_vpn_nft "${name}" 1; then
        remove_vpn_iface "${name}"
        W_VPN_HANDSHAKE_TIMEOUT="${saved}"
        return 1
    fi
    if ! wait_vpn_handshake "${name}"; then
        remove_vpn_iface "${name}"
        apply_vpn_nft "${name}" 0 || true
        W_VPN_HANDSHAKE_TIMEOUT="${saved}"
        return 1
    fi
    refresh_vpn_ipv6 "${name}"
    apply_vpn_tunnel_routes "${name}" || true
    apply_vpn_nft "${name}" 1 || true
    W_VPN_HANDSHAKE_TIMEOUT="${saved}"
    return 0
}

finish_vpn_open() {
    local name="$1"
    set_vpn_active "${name}"
    set_vpn_state_active "${name}"
    record_vpn_attempt "${name}" 1
    restart_vpn_services
}

run_vpn_failover() {
    local home lock name try raised count
    local -a names=()
    home="$(get_vpn_home)"
    mkdir -p "${home}"
    lock="${home}/failover.lock"
    if command -v flock >/dev/null 2>&1; then
        exec 9>"${lock}"
        flock -n 9 || return 0
    fi
    load_vpn_settings
    if ! check_vpn_mode; then
        clear_vpn_network
        return 0
    fi
    name="$(get_vpn_active 2>/dev/null || true)"
    if [[ -n "${name}" ]] && check_vpn_profile_valid "${name}" && check_vpn_tunnel "${name}"; then
        record_vpn_status "${name}"
        return 0
    fi
    mapfile -t names < <(list_vpn_failover_names)
    if (( ${#names[@]} == 0 )); then
        arm_vpn_lockdown
        restart_vpn_services
        send_vpn_alert "-" "-" "-" "failover"
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.failover.none"
        return 0
    fi
    log_info "${INSTALL_WATCHER:-BASH}" "vpn.failover.start"
    for name in "${names[@]}"; do
        if check_vpn_encrypted "${name}" && ! check_vpn_passphrase; then
            record_vpn_attempt "${name}" 0
            continue
        fi
        try=1
        while (( try <= W_VPN_FAILOVER_TRIES )); do
            raised=0
            run_vpn_profile "${name}" "${W_VPN_FAILOVER_TIMEOUT}" || raised=$?
            if (( raised == 0 )); then
                finish_vpn_open "${name}"
                log_success "${INSTALL_WATCHER:-BASH}" "vpn.failover.ok" "${name}"
                return 0
            fi
            remove_vpn_iface "${name}"
            apply_vpn_nft "${name}" 0 || true
            try=$((try + 1))
        done
        record_vpn_attempt "${name}" 0
    done
    arm_vpn_lockdown
    restart_vpn_services
    send_vpn_alert "-" "-" "-" "failover"
    log_info "${INSTALL_WATCHER:-BASH}" "vpn.failover.none"
}

run_vpn_mode_off() {
    log_info "${INSTALL_WATCHER:-BASH}" "vpn.mode.start"
    set_vpn_state_mode off
    load_vpn_settings
    apply_vpn_systemd || true
    clear_vpn_network
    restart_vpn_services
    log_success "${INSTALL_WATCHER:-BASH}" "vpn.mode.off"
}

run_vpn_mode_on() {
    local active
    log_info "${INSTALL_WATCHER:-BASH}" "vpn.mode.start"
    load_vpn_settings
    active="$(get_vpn_active 2>/dev/null || true)"
    if check_vpn_mode && [[ -n "${active}" ]] && check_vpn_tunnel "${active}"; then
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.mode.same" "${active}"
        return 0
    fi
    if ! check_vpn_mode; then
        if ! check_vpn_any_valid; then
            log_error "${INSTALL_WATCHER:-BASH}" "vpn.mode.none"
        fi
        set_vpn_state_mode on
        load_vpn_settings
        apply_vpn_systemd || log_error "${INSTALL_WATCHER:-BASH}" "vpn.install.fail"
    elif ! check_vpn_any_valid; then
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.mode.hold"
        return 0
    fi
    run_vpn_failover
    log_success "${INSTALL_WATCHER:-BASH}" "vpn.mode.on"
}

run_vpn_watch() {
    local name
    load_vpn_settings
    check_vpn_mode || return 0
    check_vpn_any_valid || return 0
    name="$(get_vpn_active 2>/dev/null || true)"
    if [[ -n "${name}" ]] && check_vpn_tunnel "${name}"; then
        record_vpn_status "${name}"
        return 0
    fi
    run_vpn_failover
}
