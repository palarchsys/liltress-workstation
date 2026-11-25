#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/failover.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Bring one saved tunnel up.
# Note       : No usable tunnel closes the network.
# -----------------------------------------------------------------------------


# NetworkManager stays quiet across the full stop.
arm_vpn_nm_hold() {
    if declare -F set_vpn_nm_hold_on >/dev/null 2>&1; then
        set_vpn_nm_hold_on
        set_vpn_nm_autoconnect_all false || true
        clear_vpn_nm_all || true
        set_vpn_nm_hold_off
    fi
    return 0
}

# Tunnel devices and probe devices are deleted.
clear_vpn_failover_links() {
    ip link del "${VPN_IFACE_WG}" >/dev/null 2>&1 || true
    ip link del "${VPN_IFACE_OVPN}" >/dev/null 2>&1 || true
    ip link del wgl-probe >/dev/null 2>&1 || true
    ip link del tun-probe >/dev/null 2>&1 || true
}

# Live devices drop, then the firewall closes.
arm_vpn_lockdown() {
    local name
    load_vpn_settings
    arm_vpn_nm_hold
    name="$(get_vpn_active 2>/dev/null || true)"
    if [[ -n "${name}" ]]; then
        remove_vpn_iface "${name}"
    fi
    clear_vpn_failover_links
    clear_vpn_tunnel_routes || true
    clear_vpn_active
    apply_vpn_nft "" 0 || true
    apply_vpn_bypass_routes || true
}

# The handshake limit is restored after the attempt.
run_vpn_profile() {
    local name="$1" limit="${2:-${VPN_HANDSHAKE_TIMEOUT}}"
    local saved raised=0
    saved="${VPN_HANDSHAKE_TIMEOUT}"
    VPN_HANDSHAKE_TIMEOUT="${limit}"
    apply_vpn_profile "${name}" || raised=$?
    VPN_HANDSHAKE_TIMEOUT="${saved}"
    if ((raised != 0)); then
        return "${raised}"
    fi
    refresh_vpn_ipv6 "${name}" || true
    apply_vpn_nft "${name}" 1 || true
    return 0
}

# Services come back once the profile is active.
finish_vpn_open() {
    local name="$1"
    set_vpn_active "${name}"
    set_vpn_state_active "${name}"
    record_vpn_attempt "${name}" 1
    restart_vpn_services
}

# A busy lock lets the caller return at once.
lock_vpn_failover() {
    local home lock
    home="$(get_vpn_home)"
    mkdir -p "${home}"
    lock="${home}/failover.lock"
    if command -v flock >/dev/null 2>&1; then
        exec 9>"${lock}"
        flock -n 9 || return 1
    fi
    return 0
}

# The pass matters only with the mode on or a boot profile.
check_vpn_failover_wanted() {
    check_vpn_mode || check_vpn_boot_on
}

# A healthy active tunnel needs nothing more.
check_vpn_failover_live() {
    local name
    name="$(get_vpn_active 2>/dev/null || true)"
    [[ -n "${name}" ]] && check_vpn_profile_valid "${name}" && check_vpn_tunnel "${name}"
}

# Zero profiles turn the mode off. Any profile left closes the network.
finish_vpn_failover_none() {
    if [[ "$(get_vpn_profile_count)" == "0" ]]; then
        send_vpn_alert "-" "-" "-" "failover"
        run_vpn_mode_off
        record_vpn_log failover "-" none ""
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.failover.none"
    else
        arm_vpn_lockdown
        restart_vpn_services
        send_vpn_alert "-" "-" "-" "failover"
        record_vpn_log failover "-" hold ""
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.mode.hold"
    fi
}

# The open profile becomes the stored default when none is kept.
finish_vpn_failover_open() {
    local name="$1"
    finish_vpn_open "${name}"
    load_vpn_settings
    if [[ -z "${VPN_DEFAULT:-}" ]]; then
        set_vpn_state_default "${name}"
        load_vpn_settings
    fi
    if ! check_vpn_mode; then
        set_vpn_state_mode on
        load_vpn_settings
    fi
    apply_vpn_systemd || true
    if declare -F apply_vpn_nm_autoconnect >/dev/null 2>&1; then
        apply_vpn_nm_autoconnect || true
    fi
    if declare -F set_vpn_nm_switch_off >/dev/null 2>&1; then
        set_vpn_nm_switch_off
    fi
    record_vpn_log failover "${name}" ok ""
    log_success "${INSTALL_WATCHER:-BASH}" "vpn.failover.ok" "${name}"
}

# The same profile is attempted several times, then dropped.
run_vpn_failover_tries() {
    local name="$1" try raised
    try=1
    while ((try <= VPN_FAILOVER_TRIES)); do
        raised=0
        record_vpn_log failover "${name}" try "${try}"
        run_vpn_profile "${name}" "${VPN_FAILOVER_TIMEOUT}" || raised=$?
        if ((raised == 0)); then
            finish_vpn_failover_open "${name}"
            return 0
        fi
        remove_vpn_iface "${name}"
        apply_vpn_nft "${name}" 0 || true
        try=$((try + 1))
    done
    return 1
}

# Each candidate is attempted. The first success ends the pass.
run_vpn_failover_names() {
    local name
    for name in "$@"; do
        if check_vpn_encrypted "${name}" && ! check_vpn_passphrase; then
            continue
        fi
        run_vpn_failover_tries "${name}" && return 0
        clear_vpn_profile "${name}" "dead"
    done
    return 1
}

# One saved tunnel is brought up, or the network is closed.
run_vpn_failover() {
    local home lock name try raised count
    local -a names=()
    lock_vpn_failover || return 0
    load_vpn_settings
    if ! check_vpn_failover_wanted; then
        clear_vpn_network
        return 0
    fi
    if check_vpn_failover_live; then
        return 0
    fi
    mapfile -t names < <(list_vpn_failover_names)
    if ((${#names[@]} == 0)); then
        finish_vpn_failover_none
        return 0
    fi
    if declare -F set_vpn_nm_switch_on >/dev/null 2>&1; then
        set_vpn_nm_switch_on
    fi
    record_vpn_log failover "-" start ""
    log_info "${INSTALL_WATCHER:-BASH}" "vpn.failover.start"
    run_vpn_failover_names "${names[@]}" && return 0
    clear_vpn_failover_switch
    finish_vpn_failover_none
}

# The hold ends when no candidate came up.
clear_vpn_failover_switch() {
    if declare -F set_vpn_nm_switch_off >/dev/null 2>&1; then
        set_vpn_nm_switch_off
    fi
}

# NetworkManager drops its copy when that helper is loaded.
remove_vpn_nm_profile() {
    local name="$1"
    if declare -F remove_vpn_nm_connection >/dev/null 2>&1; then
        remove_vpn_nm_connection "${name}" || true
    fi
}

# The profile directory goes away. Integrity is visited three times.
clear_vpn_profile() {
    local name="$1" reason="${2:-rm}" total saved_defer
    [[ -n "${name}" ]] || return 1
    total="$(get_vpn_profile_count)"
    remove_vpn_iface "${name}" || true
    remove_vpn_nm_profile "${name}"
    rm -rf "$(get_vpn_profile_directory "${name}")"
    if declare -F remove_vpn_state >/dev/null 2>&1; then
        remove_vpn_state "${name}"
    fi
    if [[ "${reason}" == "dead" ]]; then
        record_vpn_log failover "${name}" drop "${reason}"
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.failover.drop" "${name}"
        refresh_vpn_integrity
        return 0
    fi
    record_vpn_log rm "${name}" ok "${reason}"
    if [[ "${total}" == "1" ]]; then
        saved_defer="${VPN_DEFER_INTEGRITY:-0}"
        VPN_DEFER_INTEGRITY=1
        run_vpn_mode_off
        VPN_DEFER_INTEGRITY="${saved_defer}"
        log_success "${INSTALL_WATCHER:-BASH}" "vpn.rm.last" "${name}"
        refresh_vpn_integrity
        return 0
    fi
    log_success "${INSTALL_WATCHER:-BASH}" "vpn.rm.ok" "${name}"
    refresh_vpn_integrity
}

# An active removal promotes the next profile onto the live tunnel.
apply_vpn_successor_live() {
    local name="$1" raised=0
    apply_vpn_profile "${name}" || raised=$?
    if ((raised != 0)); then
        remove_vpn_iface "${name}" || true
        return 1
    fi
    finish_vpn_open "${name}"
    set_vpn_state_default "${name}"
    set_vpn_state_mode on
    load_vpn_settings
    apply_vpn_systemd || true
    if declare -F apply_vpn_nm_autoconnect >/dev/null 2>&1; then
        apply_vpn_nm_autoconnect || true
    fi
    record_vpn_log rm "${name}" ok "default"
    log_success "${INSTALL_WATCHER:-BASH}" "vpn.default.promoted" "${name}"
    return 0
}

# A quiet removal stores the next profile without opening a tunnel.
record_vpn_successor() {
    local name="$1" raised=0
    if declare -F check_vpn_profile >/dev/null 2>&1; then
        check_vpn_profile "${name}" || raised=$?
    else
        raised=1
    fi
    if ((raised != 0)); then
        return 1
    fi
    record_vpn_attempt "${name}" 1
    set_vpn_state_default "${name}"
    load_vpn_settings
    apply_vpn_systemd || true
    if declare -F apply_vpn_nm_autoconnect >/dev/null 2>&1; then
        apply_vpn_nm_autoconnect || true
    fi
    record_vpn_log rm "${name}" ok "default"
    log_success "${INSTALL_WATCHER:-BASH}" "vpn.default.promoted" "${name}"
    return 0
}

# The caller reports that no profile was promoted.
finish_vpn_successor_none() {
    local was_active="$1"
    set_vpn_state_default ""
    load_vpn_settings
    apply_vpn_systemd || true
    if [[ "${was_active}" == "1" ]] && check_vpn_mode; then
        arm_vpn_lockdown
    fi
    log_info "${INSTALL_WATCHER:-BASH}" "vpn.default.promote-none"
    return 0
}

# The next saved profile takes the default place.
run_vpn_successor() {
    local was_active="$1" name raised=0
    shift
    for name in "$@"; do
        [[ -n "${name}" ]] || continue
        [[ -f "$(get_vpn_profile_directory "${name}")/meta" ]] || continue
        if [[ "${was_active}" == "1" ]]; then
            apply_vpn_successor_live "${name}" && return 0
            continue
        fi
        record_vpn_successor "${name}" && return 0
    done
    finish_vpn_successor_none "${was_active}"
    return 1
}

# The mode goes off and the network is cleared.
run_vpn_mode_off() {
    log_info "${INSTALL_WATCHER:-BASH}" "vpn.mode.start"
    set_vpn_state_mode off
    load_vpn_settings
    apply_vpn_systemd || true
    clear_vpn_network
    restart_vpn_services
    refresh_vpn_integrity
    record_vpn_log mode-off "-" ok ""
    log_success "${INSTALL_WATCHER:-BASH}" "vpn.mode.off"
}

# No saved profile can be opened.
fail_vpn_mode_none() {
    if ! check_vpn_any_valid; then
        record_vpn_log mode-on "-" fail "none"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.mode.none"
    fi
}

# The mode goes on, then a pass seeks a tunnel.
run_vpn_mode_on() {
    local active
    log_info "${INSTALL_WATCHER:-BASH}" "vpn.mode.start"
    load_vpn_settings
    active="$(get_vpn_active 2>/dev/null || true)"
    if check_vpn_mode && [[ -n "${active}" ]] && check_vpn_tunnel "${active}"; then
        record_vpn_log mode-on "${active}" ok "same"
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.mode.same" "${active}"
        return 0
    fi
    if ! check_vpn_mode; then
        fail_vpn_mode_none
        set_vpn_state_mode on
        load_vpn_settings
        apply_vpn_systemd || {
            record_vpn_log mode-on "-" fail "install"
            log_error "${INSTALL_WATCHER:-BASH}" "vpn.install.fail"
        }
    elif ! check_vpn_any_valid; then
        record_vpn_log mode-on "-" hold ""
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.mode.hold"
        return 0
    fi
    VPN_DEFER_INTEGRITY=1
    run_vpn_failover
    VPN_DEFER_INTEGRITY=0
    refresh_vpn_integrity
    record_vpn_log mode-on "-" ok ""
    log_success "${INSTALL_WATCHER:-BASH}" "vpn.mode.on"
}

# A dead tunnel starts another pass. Integrity stays deferred.
run_vpn_watch() {
    local name
    load_vpn_settings
    check_vpn_mode || return 0
    check_vpn_any_valid || return 0
    name="$(get_vpn_active 2>/dev/null || true)"
    if [[ -n "${name}" ]] && check_vpn_tunnel "${name}"; then
        return 0
    fi
    VPN_DEFER_INTEGRITY=1
    run_vpn_failover
    VPN_DEFER_INTEGRITY=0
}
