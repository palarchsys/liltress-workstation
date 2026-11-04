#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/up.sh
# Updated at : 2026-11-04
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
    local name="$1" proto dir iface runtime stripped address
    proto="$(get_vpn_meta "${name}" proto)"
    dir="$(get_vpn_profile_dir "${name}")"
    iface="$(get_vpn_meta "${name}" iface)"
    runtime="${dir}/runtime"
    if [[ "${proto}" == "wireguard" ]]; then
        check_vpn_module || return 1
        ip link del "${iface}" >/dev/null 2>&1 || true
        ip link add dev "${iface}" type wireguard
        stripped="$(mktemp "${dir}/.setconf.XXXXXX")"
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
        return 0
    fi
    if check_vpn_encrypted "${name}" && ! check_vpn_passphrase; then
        return 2
    fi
    : > "${dir}/status"
    : > "${dir}/openvpn.log"
    chmod 600 "${dir}/status" "${dir}/openvpn.log"
    ip link del "${iface}" >/dev/null 2>&1 || true
    openvpn \
        --config "${runtime}" \
        --dev "${iface}" \
        --dev-type tun \
        --route-nopull \
        --route-noexec \
        --pull-filter ignore "dhcp-option DNS" \
        --pull-filter ignore redirect-gateway \
        --connect-timeout "${W_VPN_HANDSHAKE_TIMEOUT}" \
        --connect-retry-max 1 \
        --daemon \
        --writepid "${dir}/pid" \
        --log-append "${dir}/openvpn.log" \
        --verb 3 >/dev/null 2>&1 || {
            ip link del "${iface}" >/dev/null 2>&1 || true
            return 1
        }
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
        (( age > 0 && now >= age && now - age <= W_VPN_HANDSHAKE_TIMEOUT )) || return 1
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
    return 1
}

wait_vpn_handshake() {
    local name="$1" deadline state
    deadline=$((SECONDS + W_VPN_HANDSHAKE_TIMEOUT))
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
    local name="$1" iface
    iface="$(get_vpn_meta "${name}" iface 2>/dev/null || true)"
    [[ -n "${iface}" ]] || return 1
    ip link show dev "${iface}" >/dev/null 2>&1 || return 1
    check_vpn_handshake "${name}"
}

arm_vpn_closed() {
    local name="$1"
    apply_vpn_nft "${name}" 0
    clear_vpn_conntrack "${name}"
    apply_vpn_bypass_routes
    apply_vpn_endpoint_routes "${name}"
}

fail_vpn_closed() {
    local name="$1" proto endpoint reason="${2:-up}"
    remove_vpn_iface "${name}"
    clear_vpn_tunnel_routes
    apply_vpn_nft "${name}" 0 || true
    clear_vpn_active
    proto="$(get_vpn_meta "${name}" proto 2>/dev/null || true)"
    endpoint="$(get_vpn_meta "${name}" endpoint4 2>/dev/null || true)"
    [[ -n "${endpoint}" ]] || endpoint="$(get_vpn_meta "${name}" endpoint6 2>/dev/null || true)"
    send_vpn_alert "${name}" "${proto}" "${endpoint%% *}" "${reason}"
    log_error "${INSTALL_WATCHER:-BASH}" "vpn.handshake.fail" "${name}"
}

run_vpn_up() {
    local name="$1" active raised=0
    load_vpn_settings
    check_vpn_name "${name}" || log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.bad-name" "${name}"
    [[ -f "$(get_vpn_profile_dir "${name}")/meta" ]] || log_error "${INSTALL_WATCHER:-BASH}" "vpn.rm.missing" "${name}"
    [[ -f "$(get_vpn_profile_dir "${name}")/runtime" ]] || log_error "${INSTALL_WATCHER:-BASH}" "vpn.profile.invalid" "${name}"
    if check_vpn_encrypted "${name}" && ! check_vpn_passphrase; then
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.up.agent" "${name}"
    fi
    active="$(get_vpn_active 2>/dev/null || true)"
    if [[ -n "${active}" && "${active}" != "${name}" ]]; then
        run_vpn_switch "${name}"
        return 0
    fi
    if [[ "${active}" == "${name}" ]] && check_vpn_tunnel "${name}"; then
        log_success "${INSTALL_WATCHER:-BASH}" "vpn.up.same" "${name}"
        return 0
    fi
    arm_vpn_closed "${name}" || log_error "${INSTALL_WATCHER:-BASH}" "vpn.profile.invalid" "${name}"
    apply_vpn_profile "${name}" || raised=$?
    if (( raised == 2 )); then
        apply_vpn_nft "${name}" 0 || true
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.up.agent" "${name}"
    fi
    if (( raised != 0 )); then
        fail_vpn_closed "${name}" up
    fi
    apply_vpn_tunnel_routes "${name}" || fail_vpn_closed "${name}" up
    apply_vpn_nft "${name}" 1 || fail_vpn_closed "${name}" up
    wait_vpn_handshake "${name}" || fail_vpn_closed "${name}" up
    refresh_vpn_ipv6 "${name}"
    apply_vpn_tunnel_routes "${name}" || fail_vpn_closed "${name}" up
    apply_vpn_nft "${name}" 1 || fail_vpn_closed "${name}" up
    set_vpn_active "${name}"
    log_success "${INSTALL_WATCHER:-BASH}" "vpn.up.ok" "${name}"
}
