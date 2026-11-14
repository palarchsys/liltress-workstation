#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/routes.sh
# Updated at : 2026-11-14
# Creator    : palarchsys
# =============================================================================

ensure_vpn_table() {
    local file="/etc/iproute2/rt_tables.d/liltress-vpn.conf" want current
    load_vpn_settings
    want="$(printf '%s %s\n%s %s\n' "${VPN_TABLE_ID}" "${VPN_TABLE_NAME}" "${VPN_TABLE_DIRECT_ID}" "${VPN_TABLE_DIRECT_NAME}")"
    install -d -m 755 /etc/iproute2/rt_tables.d
    if [[ -f "${file}" ]]; then
        current="$(cat "${file}")"
        [[ "${current}" == "${want}" ]] && return 0
        if declare -F copy_backup >/dev/null 2>&1; then
            copy_backup "${file}"
        fi
    fi
    printf '%s' "${want}" > "${file}"
    chmod 644 "${file}"
}

vpn_route_field() {
    local line="$1" key="$2" prev="" word
    for word in ${line}; do
        if [[ "${prev}" == "${key}" ]]; then
            printf '%s\n' "${word}"
            return 0
        fi
        prev="${word}"
    done
    return 1
}

vpn_route_is_tunnel() {
    local dev="$1"
    [[ "${dev}" == "${VPN_IFACE_OVPN}" || "${dev}" == "${VPN_IFACE_WG}" || "${dev}" == "tun-probe" || "${dev}" == "wgl-probe" ]]
}

vpn_route_lookup() {
    load_vpn_settings
    if [[ -f "$(get_vpn_home)/direct.ok" ]]; then
        printf '%s\n' "${VPN_TABLE_DIRECT_NAME}"
        return 0
    fi
    printf '%s\n' "main"
}

clear_vpn_rule_prio() {
    local prio="$1" guard=0
    while (( guard < 64 )); do
        ip rule del priority "${prio}" >/dev/null 2>&1 || return 0
        guard=$((guard + 1))
    done
}

add_vpn_rule_to() {
    local prio="$1" cidr="$2" table
    table="$(vpn_route_lookup)"
    if [[ "${cidr}" == *:* ]]; then
        ip -6 rule add priority "${prio}" to "${cidr}" lookup "${table}"
    else
        ip -4 rule add priority "${prio}" to "${cidr}" lookup "${table}"
    fi
}

add_vpn_rule_from() {
    local prio="$1" cidr="$2" table
    table="$(vpn_route_lookup)"
    if [[ "${cidr}" == *:* ]]; then
        ip -6 rule add priority "${prio}" from "${cidr}" lookup "${table}"
    else
        ip -4 rule add priority "${prio}" from "${cidr}" lookup "${table}"
    fi
}

apply_vpn_bypass_routes() {
    local cidr
    local -a cidrs=()
    load_vpn_settings
    ensure_vpn_table
    clear_vpn_rule_prio "${VPN_RULE_PRIO_BYPASS_TO}"
    clear_vpn_rule_prio "${VPN_RULE_PRIO_BYPASS_FROM}"
    mapfile -t cidrs < <(list_vpn_bypass)
    for cidr in "${cidrs[@]}"; do
        [[ -n "${cidr}" ]] || continue
        add_vpn_rule_to "${VPN_RULE_PRIO_BYPASS_TO}" "${cidr}"
        add_vpn_rule_from "${VPN_RULE_PRIO_BYPASS_FROM}" "${cidr}"
    done
    apply_vpn_ssh
}

apply_vpn_endpoint_routes() {
    local name="$1" ep4 ep6 ip table
    load_vpn_settings
    ensure_vpn_table
    clear_vpn_rule_prio "${VPN_RULE_PRIO_ENDPOINT}"
    table="$(vpn_route_lookup)"
    ep4="$(get_vpn_meta "${name}" endpoint4 2>/dev/null || true)"
    ep6="$(get_vpn_meta "${name}" endpoint6 2>/dev/null || true)"
    for ip in ${ep4}; do
        get_vpn_ipv4_parts "${ip}" >/dev/null 2>&1 || continue
        ip -4 rule add priority "${VPN_RULE_PRIO_ENDPOINT}" to "${ip}/32" lookup "${table}"
    done
    for ip in ${ep6}; do
        get_vpn_v6_groups "${ip}" >/dev/null 2>&1 || continue
        ip -6 rule add priority "${VPN_RULE_PRIO_ENDPOINT}" to "${ip}/128" lookup "${table}"
    done
}

apply_vpn_tunnel_routes() {
    clear_vpn_tunnel_routes
}

clear_vpn_tunnel_routes() {
    load_vpn_settings
    clear_vpn_rule_prio "${VPN_RULE_PRIO_TUNNEL}"
    ip route flush table "${VPN_TABLE_ID}" >/dev/null 2>&1 || true
    ip -6 route flush table "${VPN_TABLE_ID}" >/dev/null 2>&1 || true
}

apply_vpn_ssh() {
    local table
    load_vpn_settings
    ensure_vpn_table
    table="$(vpn_route_lookup)"
    clear_vpn_rule_prio "${VPN_RULE_PRIO_SSH}"
    ip -4 rule add priority "${VPN_RULE_PRIO_SSH}" fwmark "${VPN_SSH_MARK}" lookup "${table}"
    ip -6 rule add priority "${VPN_RULE_PRIO_SSH}" fwmark "${VPN_SSH_MARK}" lookup "${table}"
}

clear_vpn_routes() {
    load_vpn_settings
    clear_vpn_tunnel_routes
    clear_vpn_rule_prio "${VPN_RULE_PRIO_ENDPOINT}"
    clear_vpn_rule_prio 41
    clear_vpn_rule_prio "${VPN_RULE_PRIO_SSH}"
    clear_vpn_rule_prio "${VPN_RULE_PRIO_BYPASS_TO}"
    clear_vpn_rule_prio "${VPN_RULE_PRIO_BYPASS_FROM}"
}

remember_vpn_direct_route() {
    local line dev via v6dev="" v6via="" found=0 stamp
    load_vpn_settings
    ensure_vpn_table || return 1
    while IFS= read -r line; do
        dev="$(vpn_route_field "${line}" dev 2>/dev/null || true)"
        [[ -n "${dev}" ]] || continue
        vpn_route_is_tunnel "${dev}" && continue
        via="$(vpn_route_field "${line}" via 2>/dev/null || true)"
        found=1
        break
    done < <(ip -4 route show default 2>/dev/null)
    (( found == 1 )) || return 1
    ip route flush table "${VPN_TABLE_DIRECT_ID}" >/dev/null 2>&1 || true
    if [[ -n "${via}" ]]; then
        ip route replace default via "${via}" dev "${dev}" table "${VPN_TABLE_DIRECT_ID}" >/dev/null 2>&1 || return 1
    else
        ip route replace default dev "${dev}" table "${VPN_TABLE_DIRECT_ID}" >/dev/null 2>&1 || return 1
    fi
    v6dev=""
    while IFS= read -r line; do
        v6dev="$(vpn_route_field "${line}" dev 2>/dev/null || true)"
        [[ -n "${v6dev}" ]] || continue
        if vpn_route_is_tunnel "${v6dev}"; then
            v6dev=""
            continue
        fi
        v6via="$(vpn_route_field "${line}" via 2>/dev/null || true)"
        break
    done < <(ip -6 route show default 2>/dev/null)
    ip -6 route flush table "${VPN_TABLE_DIRECT_ID}" >/dev/null 2>&1 || true
    if [[ -n "${v6dev}" ]]; then
        if [[ -n "${v6via}" ]]; then
            ip -6 route replace default via "${v6via}" dev "${v6dev}" table "${VPN_TABLE_DIRECT_ID}" >/dev/null 2>&1 || true
        else
            ip -6 route replace default dev "${v6dev}" table "${VPN_TABLE_DIRECT_ID}" >/dev/null 2>&1 || true
        fi
    fi
    stamp="$(get_vpn_home)/direct.ok"
    printf '1\n' > "${stamp}"
    chmod 600 "${stamp}"
}

release_vpn_direct() {
    load_vpn_settings
    ip route flush table "${VPN_TABLE_DIRECT_ID}" >/dev/null 2>&1 || true
    ip -6 route flush table "${VPN_TABLE_DIRECT_ID}" >/dev/null 2>&1 || true
    rm -f "$(get_vpn_home)/direct.ok"
    apply_vpn_ssh || true
}
