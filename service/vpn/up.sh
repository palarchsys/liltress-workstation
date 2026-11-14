#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/up.sh
# Updated at : 2026-11-14
# Creator    : palarchsys
# =============================================================================

check_vpn_module() {
    [[ -d /sys/module/wireguard ]] && return 0
    modprobe wireguard >/dev/null 2>&1 || return 1
    [[ -d /sys/module/wireguard ]]
}

strip_vpn_wg() {
    local src="$1" dest="$2" line trimmed section="" key private
    private="$(get_vpn_private_field)"
    : > "${dest}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        trimmed="$(strip_vpn_text "${line}")"
        if [[ "${trimmed}" == \[*\] ]]; then
            section="${trimmed#[}"
            section="${section%]}"
            printf '%s\n' "${trimmed}" >> "${dest}"
            continue
        fi
        [[ -z "${trimmed}" || "${trimmed}" == \#* ]] && continue
        key="${trimmed%%=*}"
        key="$(strip_vpn_text "${key}")"
        case "${section}:${key}" in
            "Interface:${private}"|Interface:ListenPort|Interface:FwMark|Peer:PublicKey|Peer:PresharedKey|Peer:AllowedIPs|Peer:Endpoint|Peer:PersistentKeepalive)
                printf '%s\n' "${trimmed}" >> "${dest}"
                ;;
        esac
    done < "${src}"
    chmod 600 "${dest}"
}

set_vpn_active() {
    local file
    file="$(get_vpn_home)/active"
    printf '%s\n' "$1" > "${file}"
    chmod 600 "${file}"
}

clear_vpn_active() {
    rm -f "$(get_vpn_home)/active"
}

remove_vpn_iface() {
    local name="$1" iface pid file
    [[ -n "${name}" ]] || return 0
    file="$(get_vpn_profile_dir "${name}")/pid"
    if [[ -f "${file}" ]]; then
        pid="$(tr -d '[:space:]' < "${file}")"
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

refresh_vpn_ipv6() {
    local name="$1" iface addr v6=0 meta
    iface="$(get_vpn_meta "${name}" iface)"
    while IFS= read -r addr; do
        addr="${addr%%/*}"
        if check_vpn_addr_v6 "${addr}"; then
            v6=1
        fi
    done < <(ip -6 -o addr show dev "${iface}" 2>/dev/null | awk '{print $4}')
    meta="$(get_vpn_profile_dir "${name}")/meta"
    sed -i "s/^has_ipv6=.*/has_ipv6=${v6}/" "${meta}"
    chmod 600 "${meta}"
}

apply_vpn_profile() {
    local name="$1"
    if check_vpn_encrypted "${name}" && ! check_vpn_passphrase; then
        return 2
    fi
    raise_vpn_link "${name}"
}

check_vpn_handshake() {
    local name="$1" proto iface dir now age
    proto="$(get_vpn_meta "${name}" proto)"
    iface="$(get_vpn_meta "${name}" iface)"
    dir="$(get_vpn_profile_dir "${name}")"
    now="$(date +%s)"
    if [[ "${proto}" == "wireguard" ]]; then
        age="$(wg show "${iface}" latest-handshakes 2>/dev/null | awk 'NF { print $NF; exit }')"
        [[ "${age}" =~ ^[0-9]+$ ]] || return 1
        (( age > 0 && now >= age && now - age <= VPN_HANDSHAKE_TIMEOUT )) || return 1
        printf '%s\n' "${now}" > "${dir}/handshake"
        chmod 600 "${dir}/handshake"
        return 0
    fi
    if [[ -f "${dir}/openvpn.log" ]] && grep -q 'AUTH_FAILED' "${dir}/openvpn.log"; then
        return 2
    fi
    if [[ -f "${dir}/openvpn.log" ]] && grep -q 'Initialization Sequence Completed' "${dir}/openvpn.log"; then
        printf 'CONNECTED\n' > "${dir}/status"
        printf '%s\n' "${now}" > "${dir}/handshake"
        chmod 600 "${dir}/status" "${dir}/handshake"
        return 0
    fi
    if [[ -f "${dir}/openvpn.log" ]] && grep -Eq 'Options error|TLS Error|VERIFY ERROR' "${dir}/openvpn.log"; then
        return 2
    fi
    return 1
}

wait_vpn_handshake() {
    local name="$1" deadline state
    deadline=$((SECONDS + VPN_HANDSHAKE_TIMEOUT))
    while (( SECONDS <= deadline )); do
        state=0
        check_vpn_handshake "${name}" || state=$?
        if (( state == 0 )); then
            return 0
        fi
        if (( state == 2 )); then
            return 1
        fi
        sleep 1
    done
    return 1
}

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
    if declare -F vpn_nm_activated >/dev/null 2>&1 && vpn_nm_activated "${name}"; then
        return 0
    fi
    check_vpn_handshake "${name}"
}

wait_vpn_iface() {
    local name="$1" iface deadline
    iface="$(get_vpn_meta "${name}" iface 2>/dev/null || true)"
    [[ -n "${iface}" ]] || return 1
    deadline=$((SECONDS + ${VPN_HANDSHAKE_TIMEOUT:-25}))
    while (( SECONDS <= deadline )); do
        if ip link show dev "${iface}" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

arm_vpn_closed() {
    local name="$1"
    apply_vpn_nft "${name}" 0
    clear_vpn_conntrack "${name}"
    apply_vpn_bypass_routes
    apply_vpn_endpoint_routes "${name}"
}

add_vpn_probe_routes() {
    local name="$1" ep4 ep6 ip table
    load_vpn_settings
    if declare -F vpn_route_lookup >/dev/null 2>&1; then
        table="$(vpn_route_lookup)"
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

clear_vpn_probe() {
    local iface="$1" dir="$2" pid
    if [[ -f "${dir}/probe.pid" ]]; then
        pid="$(tr -d '[:space:]' < "${dir}/probe.pid")"
        if [[ "${pid}" =~ ^[0-9]+$ ]]; then
            kill "${pid}" >/dev/null 2>&1 || true
        fi
        rm -f "${dir}/probe.pid"
    fi
    if [[ -n "${iface}" ]]; then
        ip link del "${iface}" >/dev/null 2>&1 || true
    fi
    clear_vpn_rule_prio 41
}

apply_vpn_probe() {
    local name="$1" proto dir iface runtime stripped address
    proto="$(get_vpn_meta "${name}" proto)"
    dir="$(get_vpn_profile_dir "${name}")"
    runtime="${dir}/runtime"
    if [[ "${proto}" == "wireguard" ]]; then
        iface="wgl-probe"
        check_vpn_module || return 1
        ip link del "${iface}" >/dev/null 2>&1 || true
        ip link add dev "${iface}" type wireguard
        stripped="$(mktemp "${dir}/.probe.XXXXXX")"
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
    fi
    iface="tun-probe"
    if check_vpn_encrypted "${name}" && ! check_vpn_passphrase; then
        return 2
    fi
    : > "${dir}/probe.log"
    chmod 600 "${dir}/probe.log"
    ip link del "${iface}" >/dev/null 2>&1 || true
    openvpn \
        --cd "${dir}" \
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
        --writepid "${dir}/probe.pid" \
        --log-append "${dir}/probe.log" \
        --verb 3 >/dev/null 2>&1 || {
            ip link del "${iface}" >/dev/null 2>&1 || true
            return 1
        }
    printf '%s\n' "${iface}"
}

check_vpn_probe() {
    local name="$1" iface="$2" proto dir now age
    proto="$(get_vpn_meta "${name}" proto)"
    dir="$(get_vpn_profile_dir "${name}")"
    now="$(date +%s)"
    if [[ "${proto}" == "wireguard" ]]; then
        age="$(wg show "${iface}" latest-handshakes 2>/dev/null | awk 'NF { print $NF; exit }')"
        [[ "${age}" =~ ^[0-9]+$ ]] || return 1
        (( age > 0 && now >= age && now - age <= VPN_HANDSHAKE_TIMEOUT )) || return 1
        return 0
    fi
    if [[ -f "${dir}/probe.log" ]] && grep -q 'AUTH_FAILED' "${dir}/probe.log"; then
        return 2
    fi
    if [[ -f "${dir}/probe.log" ]] && grep -q 'Initialization Sequence Completed' "${dir}/probe.log"; then
        return 0
    fi
    if [[ -f "${dir}/probe.log" ]] && grep -Eq 'Options error|TLS Error|VERIFY ERROR' "${dir}/probe.log"; then
        return 2
    fi
    return 1
}

wait_vpn_probe() {
    local name="$1" iface="$2" deadline state
    deadline=$((SECONDS + VPN_HANDSHAKE_TIMEOUT))
    while (( SECONDS <= deadline )); do
        state=0
        check_vpn_probe "${name}" "${iface}" || state=$?
        if (( state == 0 )); then
            return 0
        fi
        if (( state == 2 )); then
            return 1
        fi
        sleep 1
    done
    return 1
}

run_vpn_probe() {
    local name="$1" active="$2" iface="" raised=0 dir
    dir="$(get_vpn_profile_dir "${name}")"
    if check_vpn_encrypted "${name}" && ! check_vpn_passphrase; then
        return 2
    fi
    add_vpn_probe_routes "${name}" || return 1
    if ! apply_vpn_nft "${active}" 1 "${name}"; then
        clear_vpn_rule_prio 41
        return 1
    fi
    iface="$(apply_vpn_probe "${name}")" || raised=$?
    if (( raised != 0 )); then
        clear_vpn_probe "wgl-probe" "${dir}"
        clear_vpn_probe "tun-probe" "${dir}"
        apply_vpn_nft "${active}" 1 || true
        return "${raised}"
    fi
    if declare -F vpn_nm_unmanage >/dev/null 2>&1; then
        vpn_nm_unmanage "${iface}"
    fi
    if ! wait_vpn_probe "${name}" "${iface}"; then
        if declare -F vpn_nm_unmanage >/dev/null 2>&1; then
            vpn_nm_unmanage "${iface}"
        fi
        clear_vpn_probe "${iface}" "${dir}"
        apply_vpn_nft "${active}" 1 || true
        return 1
    fi
    if declare -F vpn_nm_unmanage >/dev/null 2>&1; then
        vpn_nm_unmanage "${iface}"
    fi
    clear_vpn_probe "${iface}" "${dir}"
    apply_vpn_nft "${active}" 1 || true
    return 0
}

vpn_fault_line() {
    local file="$1" line path base guard=0
    [[ -f "${file}" && ! -L "${file}" ]] || return 1
    line="$(grep -E 'AUTH_FAILED|Options error|TLS Error|VERIFY ERROR|Cannot ioctl TUNSETIFF' "${file}" | head -n 1 || true)"
    [[ -n "${line}" ]] || return 1
    while [[ "${line}" =~ (/[^[:space:]\'\"]+) ]]; do
        guard=$((guard + 1))
        (( guard > 8 )) && break
        path="${BASH_REMATCH[1]}"
        base="$(basename -- "${path}")"
        [[ "${base}" == "${path}" ]] && break
        line="${line//"${path}"/"${base}"}"
    done
    printf '%s' "${line}"
}

report_vpn_fail() {
    local name="$1" dir line file
    if [[ "${VPN_NM_FAULT:-}" == "load" || "${VPN_NM_FAULT:-}" == "up" ]]; then
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.nm.fail" "${name}"
        note_vpn_log test "${name}" fail "networkmanager ${VPN_NM_FAULT}"
        return 0
    fi
    dir="$(get_vpn_profile_dir "${name}")"
    for file in "${dir}/openvpn.log" "${dir}/probe.log"; do
        [[ -f "${file}" ]] || continue
        if grep -q 'AUTH_FAILED' "${file}"; then
            log_info "${INSTALL_WATCHER:-BASH}" "vpn.import.auth-failed" "${name}"
            note_vpn_log test "${name}" fail "AUTH_FAILED"
            return 0
        fi
    done
    for file in "${dir}/openvpn.log" "${dir}/probe.log"; do
        line="$(vpn_fault_line "${file}" 2>/dev/null || true)"
        [[ -n "${line}" ]] || continue
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.test.fail-reason" "${name}" "${line}"
        note_vpn_log test "${name}" fail "${line}"
        return 0
    done
    log_info "${INSTALL_WATCHER:-BASH}" "vpn.test.fail" "${name}"
    note_vpn_log test "${name}" fail ""
}

prove_vpn_profile() {
    local name="$1" armed=0 iface="" raised=0 dir
    dir="$(get_vpn_profile_dir "${name}")"
    if check_vpn_killswitch; then
        armed=1
        apply_vpn_nft "" 0 "${name}" || return 1
    fi
    if ! add_vpn_probe_routes "${name}"; then
        clear_vpn_rule_prio 41
        if (( armed == 1 )); then
            apply_vpn_nft "" 0 || true
        fi
        return 1
    fi
    iface="$(apply_vpn_probe "${name}")" || raised=$?
    if (( raised != 0 )); then
        clear_vpn_probe "wgl-probe" "${dir}"
        clear_vpn_probe "tun-probe" "${dir}"
        if (( armed == 1 )); then
            apply_vpn_nft "" 0 || true
        fi
        return "${raised}"
    fi
    if declare -F vpn_nm_unmanage >/dev/null 2>&1; then
        vpn_nm_unmanage "${iface}"
    fi
    if ! wait_vpn_probe "${name}" "${iface}"; then
        if declare -F vpn_nm_unmanage >/dev/null 2>&1; then
            vpn_nm_unmanage "${iface}"
        fi
        clear_vpn_probe "${iface}" "${dir}"
        if (( armed == 1 )); then
            apply_vpn_nft "" 0 || true
        fi
        return 1
    fi
    if declare -F vpn_nm_unmanage >/dev/null 2>&1; then
        vpn_nm_unmanage "${iface}"
    fi
    clear_vpn_probe "${iface}" "${dir}"
    if (( armed == 1 )); then
        apply_vpn_nft "" 0 || true
    fi
    return 0
}

run_vpn_test() {
    local name="${1:-}" active first=0 raised=0 auth_file
    VPN_NM_FAULT=""
    load_vpn_settings
    check_vpn_name "${name}" || log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.bad-name" "${name}"
    [[ -f "$(get_vpn_profile_dir "${name}")/runtime" ]] || log_error "${INSTALL_WATCHER:-BASH}" "vpn.profile.invalid" "${name}"
    log_info "${INSTALL_WATCHER:-BASH}" "vpn.test.start" "${name}"
    note_vpn_log test "${name}" start ""
    auth_file="$(get_vpn_profile_dir "${name}")/auth.txt"
    if [[ -f "${auth_file}" ]] && ! check_vpn_auth_file "${auth_file}"; then
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.import.auth-wait" "${name}" "${auth_file}"
        note_vpn_log test "${name}" fail "auth-wait"
        return 1
    fi
    active="$(get_vpn_active 2>/dev/null || true)"
    if [[ -n "${active}" && "${active}" == "${name}" ]] && check_vpn_tunnel "${name}"; then
        record_vpn_attempt "${name}" 1
        log_success "${INSTALL_WATCHER:-BASH}" "vpn.test.ok" "${name}"
        note_vpn_log test "${name}" ok "up"
        return 0
    fi
    if check_vpn_mode && [[ -n "${active}" && "${active}" != "${name}" ]] && check_vpn_tunnel "${active}"; then
        raised=0
        prove_vpn_profile "${name}" || raised=$?
        if (( raised == 0 )); then
            if ! VPN_NM_AUTOCONNECT=0 install_vpn_nm_connection "${name}"; then
                VPN_NM_FAULT="load"
                record_vpn_attempt "${name}" 0
                report_vpn_fail "${name}"
                return 1
            fi
            record_vpn_attempt "${name}" 1
            log_success "${INSTALL_WATCHER:-BASH}" "vpn.test.kept" "${name}"
            note_vpn_log test "${name}" ok "kept"
            return 0
        fi
        record_vpn_attempt "${name}" 0
        report_vpn_fail "${name}"
        return 1
    fi
    if ! check_vpn_had_valid; then
        first=1
    fi
    raised=0
    prove_vpn_profile "${name}" || raised=$?
    if (( raised != 0 )); then
        record_vpn_attempt "${name}" 0
        if check_vpn_mode; then
            arm_vpn_lockdown
        else
            clear_vpn_network
        fi
        report_vpn_fail "${name}"
        return 1
    fi
    if (( first == 1 )); then
        set_vpn_state_mode on
        load_vpn_settings
        apply_vpn_systemd || true
        raised=0
        apply_vpn_profile "${name}" || raised=$?
        if (( raised != 0 )); then
            set_vpn_state_mode off
            load_vpn_settings
            apply_vpn_systemd || true
            if declare -F remove_vpn_nm_connection >/dev/null 2>&1; then
                remove_vpn_nm_connection "${name}" || true
            fi
            clear_vpn_network
            record_vpn_attempt "${name}" 0
            report_vpn_fail "${name}"
            return 1
        fi
        finish_vpn_open "${name}"
        log_success "${INSTALL_WATCHER:-BASH}" "vpn.mode.on"
        note_vpn_log test "${name}" ok "mode"
        return 0
    fi
    if check_vpn_mode; then
        raised=0
        apply_vpn_profile "${name}" || raised=$?
        if (( raised != 0 )); then
            if check_vpn_mode; then
                arm_vpn_lockdown
            else
                clear_vpn_network
            fi
            record_vpn_attempt "${name}" 0
            report_vpn_fail "${name}"
            return 1
        fi
        finish_vpn_open "${name}"
        log_success "${INSTALL_WATCHER:-BASH}" "vpn.test.ok" "${name}"
        note_vpn_log test "${name}" ok "open"
        return 0
    fi
    if ! VPN_NM_AUTOCONNECT=0 install_vpn_nm_connection "${name}"; then
        VPN_NM_FAULT="load"
        record_vpn_attempt "${name}" 0
        clear_vpn_network
        report_vpn_fail "${name}"
        return 1
    fi
    record_vpn_attempt "${name}" 1
    clear_vpn_network
    log_success "${INSTALL_WATCHER:-BASH}" "vpn.test.ok" "${name}"
    note_vpn_log test "${name}" ok "open"
    return 0
}
