#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/up.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Prove a profile and bring its tunnel up.
# Note       : A failed proof removes the temporary interface.
# -----------------------------------------------------------------------------


# WireGuard is usable when its kernel module is present.
check_vpn_module() {
    [[ -d /sys/module/wireguard ]] && return 0
    modprobe wireguard >/dev/null 2>&1 || return 1
    [[ -d /sys/module/wireguard ]]
}

# Retain only the peer fields a short-lived interface needs.
strip_vpn_wg() {
    local src="$1" dest="$2" line trimmed section="" key private
    private="$(get_vpn_private_field)"
    : >"${dest}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        trimmed="$(strip_vpn_text "${line}")"
        if [[ "${trimmed}" == \[*\] ]]; then
            section="${trimmed#[}"
            section="${section%]}"
            printf '%s\n' "${trimmed}" >>"${dest}"
            continue
        fi
        [[ -z "${trimmed}" || "${trimmed}" == \#* ]] && continue
        key="${trimmed%%=*}"
        key="$(strip_vpn_text "${key}")"
        case "${section}:${key}" in
            "Interface:${private}" | Interface:ListenPort | Interface:FwMark | Peer:PublicKey | Peer:PresharedKey | Peer:AllowedIPs | Peer:Endpoint | Peer:PersistentKeepalive)
                printf '%s\n' "${trimmed}" >>"${dest}"
                ;;
        esac
    done <"${src}"
    chmod 600 "${dest}"
}

# Remember which profile owns the live tunnel.
set_vpn_active() {
    local file
    file="$(get_vpn_home)/active"
    printf '%s\n' "$1" >"${file}"
    chmod 600 "${file}"
}

# Forget the live profile when the tunnel stops.
clear_vpn_active() {
    rm -f "$(get_vpn_home)/active"
}

# Stop a leftover process and delete its interface.
remove_vpn_iface() {
    local name="$1" iface pid file
    [[ -n "${name}" ]] || return 0
    file="$(get_vpn_profile_directory "${name}")/pid"
    if [[ -f "${file}" ]]; then
        pid="$(tr -d '[:space:]' <"${file}")"
        if [[ "${pid}" =~ ^[0-9]+$ ]]; then
            kill "${pid}" >/dev/null 2>&1 || true
        fi
        rm -f "${file}"
    fi
    iface="$(get_vpn_meta "${name}" iface 2>/dev/null || true)"
    if [[ -n "${iface}" ]]; then
        ip link del "${iface}" >/dev/null 2>&1 || true
    fi
}

# Record whether the live interface has an IPv6 address.
refresh_vpn_ipv6() {
    local name="$1" iface addr v6=0 meta
    iface="$(get_vpn_meta "${name}" iface)"
    while IFS= read -r addr; do
        addr="${addr%%/*}"
        if check_vpn_addr_v6 "${addr}"; then
            v6=1
        fi
    done < <(ip -6 -o addr show dev "${iface}" 2>/dev/null | awk '{print $4}')
    meta="$(get_vpn_profile_directory "${name}")/meta"
    sed -i "s/^has_ipv6=.*/has_ipv6=${v6}/" "${meta}"
    chmod 600 "${meta}"
}

# Bring the chosen profile up, or refuse a locked secret.
apply_vpn_profile() {
    local name="$1"
    if check_vpn_encrypted "${name}" && ! check_vpn_passphrase; then
        return 2
    fi
    set_vpn_link "${name}"
}

# Accept a recent WireGuard greeting.
check_vpn_wg_age() {
    local iface="$1" now="$2" age
    age="$(wg show "${iface}" latest-handshakes 2>/dev/null | awk 'NF { print $NF; exit }')"
    [[ "${age}" =~ ^[0-9]+$ ]] || return 1
    ((age > 0 && now >= age && now - age <= VPN_HANDSHAKE_TIMEOUT)) || return 1
}

# OpenVPN journal: 2 is a hard refusal, 0 means the greeting finished.
read_vpn_ovpn_state() {
    local file="$1"
    if [[ -f "${file}" ]] && grep -q 'AUTH_FAILED' "${file}"; then
        return 2
    fi
    if [[ -f "${file}" ]] && grep -q 'Initialization Sequence Completed' "${file}"; then
        return 0
    fi
    if [[ -f "${file}" ]] && grep -Eq 'Options error|TLS Error|VERIFY ERROR' "${file}"; then
        return 2
    fi
    return 1
}

# Store a success stamp when the OpenVPN journal says the greeting finished.
check_vpn_ovpn_handshake() {
    local directory="$1" now="$2" state=0
    read_vpn_ovpn_state "${directory}/openvpn.log" || state=$?
    if ((state == 0)); then
        printf 'CONNECTED\n' >"${directory}/status"
        printf '%s\n' "${now}" >"${directory}/handshake"
        chmod 600 "${directory}/status" "${directory}/handshake"
        return 0
    fi
    return "${state}"
}

# Decide whether the live tunnel finished its greeting.
check_vpn_handshake() {
    local name="$1" proto iface directory now
    proto="$(get_vpn_meta "${name}" proto)"
    iface="$(get_vpn_meta "${name}" iface)"
    directory="$(get_vpn_profile_directory "${name}")"
    now="$(date +%s)"
    if [[ "${proto}" == "wireguard" ]]; then
        check_vpn_wg_age "${iface}" "${now}" || return 1
        printf '%s\n' "${now}" >"${directory}/handshake"
        chmod 600 "${directory}/handshake"
        return 0
    fi
    check_vpn_ovpn_handshake "${directory}" "${now}" || return $?
    return 0
}

# Poll the greeting until it succeeds or the clock runs out.
wait_vpn_handshake() {
    local name="$1" deadline state
    deadline=$((SECONDS + VPN_HANDSHAKE_TIMEOUT))
    while ((SECONDS <= deadline)); do
        state=0
        check_vpn_handshake "${name}" || state=$?
        if ((state == 0)); then
            return 0
        fi
        if ((state == 2)); then
            return 1
        fi
        sleep 1
    done
    return 1
}

# The interface exists and the greeting is healthy.
check_vpn_tunnel() {
    local name="$1" iface proto
    iface="$(get_vpn_meta "${name}" iface 2>/dev/null || true)"
    [[ -n "${iface}" ]] || return 1
    ip link show dev "${iface}" >/dev/null 2>&1 || return 1
    proto="$(get_vpn_meta "${name}" proto 2>/dev/null || true)"
    if [[ "${proto}" == "wireguard" ]]; then
        check_vpn_handshake "${name}"
        return
    fi
    if declare -F check_vpn_nm_activated >/dev/null 2>&1 && check_vpn_nm_activated "${name}"; then
        return 0
    fi
    check_vpn_handshake "${name}"
}

# Poll until the interface appears.
wait_vpn_iface() {
    local name="$1" iface deadline
    iface="$(get_vpn_meta "${name}" iface 2>/dev/null || true)"
    [[ -n "${iface}" ]] || return 1
    deadline=$((SECONDS + ${VPN_HANDSHAKE_TIMEOUT:-25}))
    while ((SECONDS <= deadline)); do
        if ip link show dev "${iface}" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# Close the network around one profile.
arm_vpn_closed() {
    local name="$1"
    apply_vpn_nft "${name}" 0
    clear_vpn_conntrack "${name}"
    apply_vpn_bypass_routes
    apply_vpn_endpoint_routes "${name}"
}

# Let the probe reach its endpoint on the current table.
add_vpn_probe_routes() {
    local name="$1" ep4 ep6 ip table
    load_vpn_settings
    if declare -F get_vpn_route_lookup >/dev/null 2>&1; then
        table="$(get_vpn_route_lookup)"
    else
        table="main"
    fi
    clear_vpn_rule_prio 41
    ep4="$(get_vpn_meta "${name}" endpoint4 2>/dev/null || true)"
    ep6="$(get_vpn_meta "${name}" endpoint6 2>/dev/null || true)"
    for ip in ${ep4}; do
        get_vpn_ipv4_parts "${ip}" >/dev/null 2>&1 || continue
        ip -4 rule add priority 41 to "${ip}/32" lookup "${table}"
    done
    for ip in ${ep6}; do
        get_vpn_v6_groups "${ip}" >/dev/null 2>&1 || continue
        ip -6 rule add priority 41 to "${ip}/128" lookup "${table}"
    done
}

# Stop the probe process and delete its interface.
clear_vpn_probe() {
    local iface="$1" directory="$2" pid
    if [[ -f "${directory}/probe.pid" ]]; then
        pid="$(tr -d '[:space:]' <"${directory}/probe.pid")"
        if [[ "${pid}" =~ ^[0-9]+$ ]]; then
            kill "${pid}" >/dev/null 2>&1 || true
        fi
        rm -f "${directory}/probe.pid"
    fi
    if [[ -n "${iface}" ]]; then
        ip link del "${iface}" >/dev/null 2>&1 || true
    fi
    clear_vpn_rule_prio 41
}

# Start a temporary WireGuard interface.
apply_vpn_probe_wireguard() {
    local directory="$1" runtime="$2" iface="wgl-probe" stripped address
    check_vpn_module || return 1
    ip link del "${iface}" >/dev/null 2>&1 || true
    ip link add dev "${iface}" type wireguard
    stripped="$(mktemp "${directory}/.probe.XXXXXX")"
    strip_vpn_wg "${runtime}" "${stripped}"
    if ! wg setconf "${iface}" "${stripped}" >/dev/null 2>&1; then
        rm -f "${stripped}"
        ip link del "${iface}" >/dev/null 2>&1 || true
        return 1
    fi
    rm -f "${stripped}"
    while IFS= read -r address; do
        ip addr replace "${address}" dev "${iface}"
    done < <(list_vpn_wg_addresses "${runtime}")
    ip link set "${iface}" up
    printf '%s\n' "${iface}"
    return 0
}

# Start a temporary OpenVPN process with no pulled routes.
apply_vpn_probe_openvpn() {
    local name="$1" directory="$2" runtime="$3" iface="tun-probe"
    if check_vpn_encrypted "${name}" && ! check_vpn_passphrase; then
        return 2
    fi
    : >"${directory}/probe.log"
    chmod 600 "${directory}/probe.log"
    ip link del "${iface}" >/dev/null 2>&1 || true
    openvpn \
        --cd "${directory}" \
        --config "${runtime}" \
        --dev "${iface}" \
        --dev-type tun \
        --route-nopull \
        --route-noexec \
        --pull-filter ignore "dhcp-option DNS" \
        --pull-filter ignore redirect-gateway \
        --pull-filter ignore route-ipv6 \
        --connect-timeout "${VPN_HANDSHAKE_TIMEOUT}" \
        --connect-retry-max 1 \
        --daemon \
        --writepid "${directory}/probe.pid" \
        --log-append "${directory}/probe.log" \
        --verb 3 >/dev/null 2>&1 || {
        ip link del "${iface}" >/dev/null 2>&1 || true
        return 1
    }
    printf '%s\n' "${iface}"
}

# Start the probe that matches the profile protocol.
apply_vpn_probe() {
    local name="$1" proto directory runtime
    proto="$(get_vpn_meta "${name}" proto)"
    directory="$(get_vpn_profile_directory "${name}")"
    runtime="${directory}/runtime"
    if [[ "${proto}" == "wireguard" ]]; then
        apply_vpn_probe_wireguard "${directory}" "${runtime}" || return $?
        return 0
    fi
    apply_vpn_probe_openvpn "${name}" "${directory}" "${runtime}" || return $?
    return 0
}

# Decide whether the probe finished its greeting.
check_vpn_probe() {
    local name="$1" iface="$2" proto directory now
    proto="$(get_vpn_meta "${name}" proto)"
    directory="$(get_vpn_profile_directory "${name}")"
    now="$(date +%s)"
    if [[ "${proto}" == "wireguard" ]]; then
        check_vpn_wg_age "${iface}" "${now}" || return $?
        return 0
    fi
    read_vpn_ovpn_state "${directory}/probe.log" || return $?
    return 0
}

# Poll the probe until it succeeds or the clock runs out.
wait_vpn_probe() {
    local name="$1" iface="$2" deadline state
    deadline=$((SECONDS + VPN_HANDSHAKE_TIMEOUT))
    while ((SECONDS <= deadline)); do
        state=0
        check_vpn_probe "${name}" "${iface}" || state=$?
        if ((state == 0)); then
            return 0
        fi
        if ((state == 2)); then
            return 1
        fi
        sleep 1
    done
    return 1
}

# Hand the interface back when NetworkManager is present.
clear_vpn_probe_iface() {
    local iface="$1"
    if declare -F set_vpn_nm_unmanaged >/dev/null 2>&1; then
        set_vpn_nm_unmanaged "${iface}"
    fi
}

# Open routes and the packet filter before the probe.
begin_vpn_probe_link() {
    local name="$1" active="$2"
    add_vpn_probe_routes "${name}" || return 1
    if ! apply_vpn_nft "${active}" 1 "${name}"; then
        clear_vpn_rule_prio 41
        return 1
    fi
}

# Remove both probe interfaces and restore the filter.
fail_vpn_probe_link() {
    local active="$1" directory="$2"
    clear_vpn_probe "wgl-probe" "${directory}"
    clear_vpn_probe "tun-probe" "${directory}"
    apply_vpn_nft "${active}" 1 || true
}

# Wait, then remove the probe and restore the filter.
finish_vpn_probe_link() {
    local name="$1" active="$2" directory="$3" iface="$4"
    clear_vpn_probe_iface "${iface}"
    if ! wait_vpn_probe "${name}" "${iface}"; then
        clear_vpn_probe_iface "${iface}"
        clear_vpn_probe "${iface}" "${directory}"
        apply_vpn_nft "${active}" 1 || true
        return 1
    fi
    clear_vpn_probe_iface "${iface}"
    clear_vpn_probe "${iface}" "${directory}"
    apply_vpn_nft "${active}" 1 || true
    return 0
}

# Prove a profile during the time another tunnel stays in place.
run_vpn_probe() {
    local name="$1" active="$2" iface="" raised=0 directory
    directory="$(get_vpn_profile_directory "${name}")"
    if check_vpn_encrypted "${name}" && ! check_vpn_passphrase; then
        return 2
    fi
    begin_vpn_probe_link "${name}" "${active}" || return 1
    iface="$(apply_vpn_probe "${name}")" || raised=$?
    if ((raised != 0)); then
        fail_vpn_probe_link "${active}" "${directory}"
        return "${raised}"
    fi
    finish_vpn_probe_link "${name}" "${active}" "${directory}" "${iface}" || return 1
    return 0
}

# First error sentence, with directory names removed.
get_vpn_fault_line() {
    local file="$1" line path base guard=0 class
    class='[^[:space:]'"'"'"]'
    [[ -f "${file}" && ! -L "${file}" ]] || return 1
    line="$(grep -E 'AUTH_FAILED|Options error|TLS Error|VERIFY ERROR|Cannot ioctl TUNSETIFF' "${file}" | head -n 1 || true)"
    [[ -n "${line}" ]] || return 1
    while [[ "${line}" =~ (/${class}+) ]]; do
        guard=$((guard + 1))
        ((guard > 8)) && break
        path="${BASH_REMATCH[1]}"
        base="$(basename -- "${path}")"
        [[ "${base}" == "${path}" ]] && break
        line="${line//"${path}"/"${base}"}"
    done
    printf '%s' "${line}"
}

# NetworkManager load and up faults use their own sentence.
report_vpn_nm_fail() {
    local name="$1"
    if [[ "${VPN_NM_FAULT:-}" == "load" || "${VPN_NM_FAULT:-}" == "up" ]]; then
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.nm.fail" "${name}"
        record_vpn_log test "${name}" fail "networkmanager ${VPN_NM_FAULT}"
        return 0
    fi
    return 1
}

# Choose the sentence a person sees after a refused proof.
report_vpn_fail() {
    local name="$1" directory line file
    report_vpn_nm_fail "${name}" && return 0
    directory="$(get_vpn_profile_directory "${name}")"
    for file in "${directory}/openvpn.log" "${directory}/probe.log"; do
        [[ -f "${file}" ]] || continue
        if grep -q 'AUTH_FAILED' "${file}"; then
            log_info "${INSTALL_WATCHER:-BASH}" "vpn.import.auth-failed" "${name}"
            record_vpn_log test "${name}" fail "AUTH_FAILED"
            return 0
        fi
    done
    for file in "${directory}/openvpn.log" "${directory}/probe.log"; do
        line="$(get_vpn_fault_line "${file}" 2>/dev/null || true)"
        [[ -n "${line}" ]] || continue
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.test.fail-reason" "${name}" "${line}"
        record_vpn_log test "${name}" fail "${line}"
        return 0
    done
    log_info "${INSTALL_WATCHER:-BASH}" "vpn.test.fail" "${name}"
    record_vpn_log test "${name}" fail ""
}

# Close the network before a proof when protection is armed.
begin_vpn_probe_guard() {
    local name="$1"
    if check_vpn_killswitch; then
        armed=1
        apply_vpn_nft "" 0 "${name}" || return 1
    fi
}

# Open the closed network again after the proof.
reset_vpn_probe_guard() {
    if ((armed == 1)); then
        apply_vpn_nft "" 0 || true
    fi
}

# Drop the probe rules and open the network again.
fail_vpn_probe_routes() {
    clear_vpn_rule_prio 41
    reset_vpn_probe_guard
}

# Delete both probe interfaces and open the network again.
fail_vpn_probe_raise() {
    local directory="$1"
    clear_vpn_probe "wgl-probe" "${directory}"
    clear_vpn_probe "tun-probe" "${directory}"
    reset_vpn_probe_guard
}

# Wait, then delete the probe interface.
finish_vpn_probe_wait() {
    local name="$1" directory="$2" iface="$3"
    clear_vpn_probe_iface "${iface}"
    if ! wait_vpn_probe "${name}" "${iface}"; then
        clear_vpn_probe_iface "${iface}"
        clear_vpn_probe "${iface}" "${directory}"
        reset_vpn_probe_guard
        return 1
    fi
    clear_vpn_probe_iface "${iface}"
    clear_vpn_probe "${iface}" "${directory}"
    reset_vpn_probe_guard
    return 0
}

# Prove a profile without leaving its probe behind.
check_vpn_profile() {
    local name="$1" armed=0 iface="" raised=0 directory
    directory="$(get_vpn_profile_directory "${name}")"
    begin_vpn_probe_guard "${name}" || return 1
    if ! add_vpn_probe_routes "${name}"; then
        fail_vpn_probe_routes
        return 1
    fi
    iface="$(apply_vpn_probe "${name}")" || raised=$?
    if ((raised != 0)); then
        fail_vpn_probe_raise "${directory}"
        return "${raised}"
    fi
    finish_vpn_probe_wait "${name}" "${directory}" "${iface}" || return 1
    return 0
}

# Refuse a bad name or a profile with no runtime file.
require_vpn_test_name() {
    check_vpn_name "${name}" || log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.bad-name" "${name}"
    [[ -f "$(get_vpn_profile_directory "${name}")/runtime" ]] || log_error "${INSTALL_WATCHER:-BASH}" "vpn.profile.invalid" "${name}"
}

# Stop when the saved login file is not usable yet.
apply_vpn_test_auth() {
    local auth_file
    auth_file="$(get_vpn_profile_directory "${name}")/auth.txt"
    if [[ -f "${auth_file}" ]] && ! check_vpn_auth_file "${auth_file}"; then
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.import.auth-wait" "${name}" "${auth_file}"
        record_vpn_log test "${name}" fail "auth-wait"
        return 1
    fi
    return 0
}

# A tunnel that is already this profile counts as success.
apply_vpn_test_same() {
    gate=""
    [[ -n "${active}" && "${active}" == "${name}" ]] && check_vpn_tunnel "${name}" || return 0
    record_vpn_attempt "${name}" 1
    log_success "${INSTALL_WATCHER:-BASH}" "vpn.test.ok" "${name}"
    record_vpn_log test "${name}" ok "up"
    gate=0
}

# Another live tunnel is proved beside, not replaced.
check_vpn_test_other_live() {
    local active="$1" name="$2"
    check_vpn_mode && [[ -n "${active}" && "${active}" != "${name}" ]] && check_vpn_tunnel "${active}"
}

# Prove beside a different live tunnel and keep that tunnel.
apply_vpn_test_other() {
    gate=""
    check_vpn_test_other_live "${active}" "${name}" || return 0
    raised=0
    check_vpn_profile "${name}" || raised=$?
    if ((raised == 0)); then
        if ! VPN_NM_AUTOCONNECT=0 install_vpn_nm_connection "${name}"; then
            VPN_NM_FAULT="load"
            record_vpn_attempt "${name}" 0
            report_vpn_fail "${name}"
            gate=1
            return 0
        fi
        record_vpn_attempt "${name}" 1
        log_success "${INSTALL_WATCHER:-BASH}" "vpn.test.kept" "${name}"
        record_vpn_log test "${name}" ok "kept"
        gate=0
        return 0
    fi
    record_vpn_attempt "${name}" 0
    report_vpn_fail "${name}"
    gate=1
}

# Run the proof and close or clear the network on a refusal.
apply_vpn_test_prove() {
    gate=""
    if ! check_vpn_had_valid; then
        first=1
    fi
    raised=0
    check_vpn_profile "${name}" || raised=$?
    ((raised == 0)) && return 0
    record_vpn_attempt "${name}" 0
    if check_vpn_mode; then
        arm_vpn_lockdown
    else
        clear_vpn_network
    fi
    report_vpn_fail "${name}"
    gate=1
}

# A refused first proof drops the NetworkManager copy when that helper is loaded.
remove_vpn_test_nm() {
    local name="$1"
    if declare -F remove_vpn_nm_connection >/dev/null 2>&1; then
        remove_vpn_nm_connection "${name}" || true
    fi
}

# The first valid profile becomes the boot profile and comes up.
apply_vpn_test_first() {
    gate=""
    ((first == 1)) || return 0
    set_vpn_state_mode on
    set_vpn_state_default "${name}"
    load_vpn_settings
    apply_vpn_systemd || true
    raised=0
    apply_vpn_profile "${name}" || raised=$?
    if ((raised != 0)); then
        set_vpn_state_default ""
        set_vpn_state_mode off
        load_vpn_settings
        apply_vpn_systemd || true
        remove_vpn_test_nm "${name}"
        clear_vpn_network
        record_vpn_attempt "${name}" 0
        report_vpn_fail "${name}"
        gate=1
        return 0
    fi
    finish_vpn_open "${name}"
    log_success "${INSTALL_WATCHER:-BASH}" "vpn.mode.on"
    record_vpn_log test "${name}" ok "mode"
    gate=0
}

# Replace the live tunnel when the mode is already on.
apply_vpn_test_open() {
    gate=""
    check_vpn_mode || return 0
    raised=0
    apply_vpn_profile "${name}" || raised=$?
    if ((raised != 0)); then
        if check_vpn_mode; then
            arm_vpn_lockdown
        else
            clear_vpn_network
        fi
        record_vpn_attempt "${name}" 0
        report_vpn_fail "${name}"
        gate=1
        return 0
    fi
    finish_vpn_open "${name}"
    log_success "${INSTALL_WATCHER:-BASH}" "vpn.test.ok" "${name}"
    record_vpn_log test "${name}" ok "open"
    gate=0
}

# Store the profile and leave the network direct.
apply_vpn_test_closed() {
    gate=""
    if ! VPN_NM_AUTOCONNECT=0 install_vpn_nm_connection "${name}"; then
        VPN_NM_FAULT="load"
        record_vpn_attempt "${name}" 0
        clear_vpn_network
        report_vpn_fail "${name}"
        gate=1
        return 0
    fi
    record_vpn_attempt "${name}" 1
    clear_vpn_network
    log_success "${INSTALL_WATCHER:-BASH}" "vpn.test.ok" "${name}"
    record_vpn_log test "${name}" ok "open"
    gate=0
}

# Prove a profile, then keep, replace, or store the result.
run_vpn_test() {
    local name="${1:-}" active first=0 raised=0 gate=""
    VPN_NM_FAULT=""
    load_vpn_settings
    require_vpn_test_name
    log_info "${INSTALL_WATCHER:-BASH}" "vpn.test.start" "${name}"
    record_vpn_log test "${name}" start ""
    apply_vpn_test_auth || return 1
    active="$(get_vpn_active 2>/dev/null || true)"
    apply_vpn_test_same
    [[ -z "${gate}" ]] || return "${gate}"
    apply_vpn_test_other
    [[ -z "${gate}" ]] || return "${gate}"
    apply_vpn_test_prove
    [[ -z "${gate}" ]] || return "${gate}"
    apply_vpn_test_first
    [[ -z "${gate}" ]] || return "${gate}"
    apply_vpn_test_open
    [[ -z "${gate}" ]] || return "${gate}"
    apply_vpn_test_closed
    return "${gate}"
}
