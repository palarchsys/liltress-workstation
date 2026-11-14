#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/failover.sh
# Updated at : 2026-11-14
# Creator    : palarchsys
# =============================================================================

arm_vpn_lockdown() {
    local name
    load_vpn_settings
    name="$(get_vpn_active 2>/dev/null || true)"
    if [[ -n "${name}" ]]; then
        remove_vpn_iface "${name}"
    fi
    ip link del "${VPN_IFACE_WG}" >/dev/null 2>&1 || true
    ip link del "${VPN_IFACE_OVPN}" >/dev/null 2>&1 || true
    ip link del wgl-probe >/dev/null 2>&1 || true
    ip link del tun-probe >/dev/null 2>&1 || true
    clear_vpn_tunnel_routes || true
    clear_vpn_active
    apply_vpn_nft "" 0 || true
    apply_vpn_bypass_routes || true
}

run_vpn_profile() {
    local name="$1" limit="${2:-${VPN_HANDSHAKE_TIMEOUT}}"
    local saved raised=0
    saved="${VPN_HANDSHAKE_TIMEOUT}"
    VPN_HANDSHAKE_TIMEOUT="${limit}"
    if check_vpn_encrypted "${name}" && ! check_vpn_passphrase; then
        VPN_HANDSHAKE_TIMEOUT="${saved}"
        return 2
    fi
    if ! arm_vpn_closed "${name}"; then
        VPN_HANDSHAKE_TIMEOUT="${saved}"
        return 1
    fi
    apply_vpn_profile "${name}" || raised=$?
    if (( raised != 0 )); then
        remove_vpn_iface "${name}"
        VPN_HANDSHAKE_TIMEOUT="${saved}"
        return "${raised}"
    fi
    if ! apply_vpn_tunnel_routes "${name}"; then
        remove_vpn_iface "${name}"
        VPN_HANDSHAKE_TIMEOUT="${saved}"
        return 1
    fi
    if ! apply_vpn_nft "${name}" 1; then
        remove_vpn_iface "${name}"
        VPN_HANDSHAKE_TIMEOUT="${saved}"
        return 1
    fi
    if ! wait_vpn_handshake "${name}"; then
        remove_vpn_iface "${name}"
        apply_vpn_nft "${name}" 0 || true
        VPN_HANDSHAKE_TIMEOUT="${saved}"
        return 1
    fi
    refresh_vpn_ipv6 "${name}"
    apply_vpn_tunnel_routes "${name}" || true
    apply_vpn_nft "${name}" 1 || true
    VPN_HANDSHAKE_TIMEOUT="${saved}"
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
        if [[ "$(count_vpn_profiles)" == "0" ]]; then
            send_vpn_alert "-" "-" "-" "failover"
            run_vpn_mode_off
            note_vpn_log failover "-" none ""
            log_info "${INSTALL_WATCHER:-BASH}" "vpn.failover.none"
        else
            arm_vpn_lockdown
            restart_vpn_services
            send_vpn_alert "-" "-" "-" "failover"
            note_vpn_log failover "-" hold ""
            log_info "${INSTALL_WATCHER:-BASH}" "vpn.mode.hold"
        fi
        return 0
    fi
    note_vpn_log failover "-" start ""
    log_info "${INSTALL_WATCHER:-BASH}" "vpn.failover.start"
    for name in "${names[@]}"; do
        if check_vpn_encrypted "${name}" && ! check_vpn_passphrase; then
            continue
        fi
        try=1
        while (( try <= VPN_FAILOVER_TRIES )); do
            raised=0
            note_vpn_log failover "${name}" try "${try}"
            run_vpn_profile "${name}" "${VPN_FAILOVER_TIMEOUT}" || raised=$?
            if (( raised == 0 )); then
                finish_vpn_open "${name}"
                note_vpn_log failover "${name}" ok ""
                log_success "${INSTALL_WATCHER:-BASH}" "vpn.failover.ok" "${name}"
                return 0
            fi
            remove_vpn_iface "${name}"
            apply_vpn_nft "${name}" 0 || true
            try=$((try + 1))
        done
        forget_vpn_profile "${name}" "dead"
    done
    if [[ "$(count_vpn_profiles)" == "0" ]]; then
        send_vpn_alert "-" "-" "-" "failover"
        run_vpn_mode_off
        note_vpn_log failover "-" none ""
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.failover.none"
    else
        arm_vpn_lockdown
        restart_vpn_services
        send_vpn_alert "-" "-" "-" "failover"
        note_vpn_log failover "-" hold ""
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.mode.hold"
    fi
}

forget_vpn_profile() {
    local name="$1" reason="${2:-rm}" total
    [[ -n "${name}" ]] || return 1
    total="$(count_vpn_profiles)"
    remove_vpn_iface "${name}" || true
    rm -rf "$(get_vpn_profile_dir "${name}")"
    if declare -F remove_vpn_state >/dev/null 2>&1; then
        remove_vpn_state "${name}"
    fi
    if [[ "${reason}" == "dead" ]]; then
        note_vpn_log failover "${name}" drop "${reason}"
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.failover.drop" "${name}"
        return 0
    fi
    note_vpn_log rm "${name}" ok "${reason}"
    if [[ "${total}" == "1" ]]; then
        run_vpn_mode_off
        log_success "${INSTALL_WATCHER:-BASH}" "vpn.rm.last" "${name}"
        return 0
    fi
    log_success "${INSTALL_WATCHER:-BASH}" "vpn.rm.ok" "${name}"
}

run_vpn_mode_off() {
    log_info "${INSTALL_WATCHER:-BASH}" "vpn.mode.start"
    set_vpn_state_mode off
    load_vpn_settings
    apply_vpn_systemd || true
    clear_vpn_network
    restart_vpn_services
    note_vpn_log mode-off "-" ok ""
    log_success "${INSTALL_WATCHER:-BASH}" "vpn.mode.off"
}

run_vpn_mode_on() {
    local active
    log_info "${INSTALL_WATCHER:-BASH}" "vpn.mode.start"
    load_vpn_settings
    active="$(get_vpn_active 2>/dev/null || true)"
    if check_vpn_mode && [[ -n "${active}" ]] && check_vpn_tunnel "${active}"; then
        note_vpn_log mode-on "${active}" ok "same"
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.mode.same" "${active}"
        return 0
    fi
    if ! check_vpn_mode; then
        if ! check_vpn_any_valid; then
            note_vpn_log mode-on "-" fail "none"
            log_error "${INSTALL_WATCHER:-BASH}" "vpn.mode.none"
        fi
        set_vpn_state_mode on
        load_vpn_settings
        apply_vpn_systemd || {
            note_vpn_log mode-on "-" fail "install"
            log_error "${INSTALL_WATCHER:-BASH}" "vpn.install.fail"
        }
    elif ! check_vpn_any_valid; then
        note_vpn_log mode-on "-" hold ""
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.mode.hold"
        return 0
    fi
    run_vpn_failover
    note_vpn_log mode-on "-" ok ""
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
