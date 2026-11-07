#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/routes.sh
# Updated at : 2026-11-05
# Creator    : palarchsys
# =============================================================================

ensure_vpn_table() {
    local file="/etc/iproute2/rt_tables.d/liltress-vpn.conf" line
    load_vpn_settings
    line="${VPN_TABLE_ID} ${VPN_TABLE_NAME}"
    install -d -m 755 /etc/iproute2/rt_tables.d
    if [[ -f "${file}" ]] && [[ "$(tr -d '[:space:]' < "${file}")" == "$(printf '%s' "${line}" | tr -d '[:space:]')" ]]; then
        return 0
    fi
    if [[ -f "${file}" ]] && declare -F copy_backup >/dev/null 2>&1; then
        copy_backup "${file}"
    fi
    printf '%s\n' "${line}" > "${file}"
    chmod 644 "${file}"
}

clear_vpn_rule_prio() {
    local prio="$1" guard=0
    while (( guard < 64 )); do
        ip rule del priority "${prio}" >/dev/null 2>&1 || return 0
        guard=$((guard + 1))
    done
}

add_vpn_rule_to() {
    local prio="$1" cidr="$2"
    if [[ "${cidr}" == *:* ]]; then
        ip -6 rule add priority "${prio}" to "${cidr}" lookup main
    else
        ip -4 rule add priority "${prio}" to "${cidr}" lookup main
    fi
}

add_vpn_rule_from() {
    local prio="$1" cidr="$2"
    if [[ "${cidr}" == *:* ]]; then
        ip -6 rule add priority "${prio}" from "${cidr}" lookup main
    else
        ip -4 rule add priority "${prio}" from "${cidr}" lookup main
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
    local name="$1" ep4 ep6 ip
    load_vpn_settings
    ensure_vpn_table
    clear_vpn_rule_prio "${VPN_RULE_PRIO_ENDPOINT}"
    ep4="$(get_vpn_meta "${name}" endpoint4 2>/dev/null || true)"
    ep6="$(get_vpn_meta "${name}" endpoint6 2>/dev/null || true)"
    for ip in ${ep4}; do
        get_vpn_ipv4_parts "${ip}" >/dev/null 2>&1 || continue
        ip -4 rule add priority "${VPN_RULE_PRIO_ENDPOINT}" to "${ip}/32" lookup main
    done
    for ip in ${ep6}; do
        get_vpn_v6_groups "${ip}" >/dev/null 2>&1 || continue
        ip -6 rule add priority "${VPN_RULE_PRIO_ENDPOINT}" to "${ip}/128" lookup main
    done
}

apply_vpn_tunnel_routes() {
    local name="$1" iface v6
    load_vpn_settings
    ensure_vpn_table
    iface="$(get_vpn_meta "${name}" iface)"
    v6="$(get_vpn_meta "${name}" has_ipv6 2>/dev/null || echo 0)"
    ip route flush table "${VPN_TABLE_ID}" >/dev/null 2>&1 || true
    ip -6 route flush table "${VPN_TABLE_ID}" >/dev/null 2>&1 || true
    ip route replace default dev "${iface}" table "${VPN_TABLE_ID}"
    if [[ "${v6}" == "1" ]]; then
        ip -6 route replace default dev "${iface}" table "${VPN_TABLE_ID}"
    fi
    clear_vpn_rule_prio "${VPN_RULE_PRIO_TUNNEL}"
    ip rule add priority "${VPN_RULE_PRIO_TUNNEL}" lookup "${VPN_TABLE_NAME}"
}

clear_vpn_tunnel_routes() {
    load_vpn_settings
    clear_vpn_rule_prio "${VPN_RULE_PRIO_TUNNEL}"
    ip route flush table "${VPN_TABLE_ID}" >/dev/null 2>&1 || true
    ip -6 route flush table "${VPN_TABLE_ID}" >/dev/null 2>&1 || true
}

apply_vpn_ssh() {
    load_vpn_settings
    ensure_vpn_table
    clear_vpn_rule_prio "${VPN_RULE_PRIO_SSH}"
    ip -4 rule add priority "${VPN_RULE_PRIO_SSH}" fwmark "${VPN_SSH_MARK}" lookup main
    ip -6 rule add priority "${VPN_RULE_PRIO_SSH}" fwmark "${VPN_SSH_MARK}" lookup main
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
