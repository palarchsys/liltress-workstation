#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/killswitch.sh
# Updated at : 2026-11-05
# Creator    : palarchsys
# =============================================================================

collect_vpn_nft() {
    local joined="" item
    for item in "$@"; do
        if [[ -n "${joined}" ]]; then
            joined+=", "
        fi
        joined+="${item}"
    done
    printf '%s' "${joined}"
}

render_vpn_nft_set() {
    local name="$1" kind="$2"
    shift 2
    if (( $# == 0 )); then
        printf '    set %s { type %s; flags interval; }\n' "${name}" "${kind}"
        return 0
    fi
    printf '    set %s { type %s; flags interval; elements = { %s } }\n' \
        "${name}" "${kind}" "$(collect_vpn_nft "$@")"
}

get_vpn_ssh_port() {
    local port="22"
    if declare -F get_ssh_port >/dev/null 2>&1; then
        get_ssh_port || true
        port="${SSH_PORT:-22}"
    fi
    [[ "${port}" =~ ^[0-9]+$ ]] || port="22"
    printf '%s\n' "${port}"
}

check_vpn_killswitch() {
    command -v nft >/dev/null 2>&1 || return 1
    nft list table inet w_vpn >/dev/null 2>&1
}

list_vpn_bypass() {
    local home applied line
    home="$(get_vpn_home)"
    applied="${home}/bypass.applied"
    if [[ -f "${home}/bypass.cidrs" ]]; then
        if ! write_vpn_bypass "${home}/bypass.cidrs" "${applied}"; then
            show_vpn_text_err vpn.bypass.kept
        fi
    fi
    list_vpn_implicit
    if [[ -f "${applied}" ]]; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            line="$(strip_vpn_text "${line}")"
            [[ -n "${line}" ]] && printf '%s\n' "${line}"
        done < "${applied}"
    fi
}

apply_vpn_nft() {
    local name="${1:-}" with_iface="${2:-0}" extra="${3:-}"
    local home tmp iface proto port transport v6 ep4 ep6 ssh_port mark
    local extra_transport="" extra_port="" extra_ep4="" extra_ep6=""
    local -a b4=() b6=() e4=() e6=() cidrs=()
    local -A seen4=() seen6=()
    local cidr ip priority
    load_vpn_settings
    priority="${W_VPN_FW_PRIORITY:--150}"
    [[ "${priority}" =~ ^-[0-9]+$ ]] || priority=-150
    home="$(get_vpn_home)"
    mkdir -p "${home}"
    mapfile -t cidrs < <(list_vpn_bypass)
    for cidr in "${cidrs[@]}"; do
        if [[ "${cidr}" == *:* ]]; then
            [[ -n "${seen6[${cidr}]+x}" ]] && continue
            seen6["${cidr}"]=1
            b6+=("${cidr}")
        else
            [[ -n "${seen4[${cidr}]+x}" ]] && continue
            seen4["${cidr}"]=1
            b4+=("${cidr}")
        fi
    done
    iface=""
    v6=0
    transport=""
    port=""
    ep4=""
    ep6=""
    if [[ -n "${name}" ]]; then
        iface="$(get_vpn_meta "${name}" iface 2>/dev/null || true)"
        v6="$(get_vpn_meta "${name}" has_ipv6 2>/dev/null || echo 0)"
        transport="$(get_vpn_meta "${name}" transport 2>/dev/null || true)"
        port="$(get_vpn_meta "${name}" port 2>/dev/null || true)"
        ep4="$(get_vpn_meta "${name}" endpoint4 2>/dev/null || true)"
        ep6="$(get_vpn_meta "${name}" endpoint6 2>/dev/null || true)"
    fi
    [[ "${transport}" == "tcp" || "${transport}" == "udp" ]] || transport=""
    [[ "${port}" =~ ^[0-9]+$ ]] || port=""
    for ip in ${ep4}; do
        get_vpn_ipv4_parts "${ip}" >/dev/null 2>&1 || continue
        e4+=("${ip}")
    done
    for ip in ${ep6}; do
        get_vpn_v6_groups "${ip}" >/dev/null 2>&1 || continue
        e6+=("${ip}")
    done
    if [[ -n "${extra}" ]]; then
        extra_transport="$(get_vpn_meta "${extra}" transport 2>/dev/null || true)"
        extra_port="$(get_vpn_meta "${extra}" port 2>/dev/null || true)"
        extra_ep4="$(get_vpn_meta "${extra}" endpoint4 2>/dev/null || true)"
        extra_ep6="$(get_vpn_meta "${extra}" endpoint6 2>/dev/null || true)"
        [[ "${extra_transport}" == "tcp" || "${extra_transport}" == "udp" ]] || extra_transport=""
        [[ "${extra_port}" =~ ^[0-9]+$ ]] || extra_port=""
    fi
    ssh_port="$(get_vpn_ssh_port)"
    mark="${W_VPN_SSH_MARK:-17820}"
    [[ "${mark}" =~ ^[0-9]+$ ]] || mark=17820
    tmp="$(mktemp "${home}/.nft.XXXXXX")"
    chmod 600 "${tmp}"
    {
        printf 'table inet w_vpn {\n'
        render_vpn_nft_set bypass4 ipv4_addr "${b4[@]}"
        render_vpn_nft_set bypass6 ipv6_addr "${b6[@]}"
        if (( ${#e4[@]} > 0 )); then
            render_vpn_nft_set endpoint4 ipv4_addr "${e4[@]/%//32}"
        else
            render_vpn_nft_set endpoint4 ipv4_addr
        fi
        if (( ${#e6[@]} > 0 )); then
            render_vpn_nft_set endpoint6 ipv6_addr "${e6[@]/%//128}"
        else
            render_vpn_nft_set endpoint6 ipv6_addr
        fi
        printf '    chain output {\n'
        printf '        type filter hook output priority %s; policy drop;\n' "${priority}"
        printf '        oifname "lo" accept\n'
        printf '        ip daddr @bypass4 accept\n'
        printf '        ip6 daddr @bypass6 accept\n'
        printf '        meta l4proto udp th sport 68 th dport 67 accept\n'
        printf '        meta l4proto udp th sport 546 th dport 547 accept\n'
        printf '        meta l4proto tcp th dport %s accept\n' "${ssh_port}"
        printf '        meta l4proto tcp th sport %s accept\n' "${ssh_port}"
        if [[ -n "${transport}" && -n "${port}" ]]; then
            for ip in "${e4[@]}"; do
                printf '        ip daddr %s meta l4proto %s th dport %s accept\n' "${ip}" "${transport}" "${port}"
            done
            for ip in "${e6[@]}"; do
                printf '        ip6 daddr %s meta l4proto %s th dport %s accept\n' "${ip}" "${transport}" "${port}"
            done
        fi
        if [[ -n "${extra_transport}" && -n "${extra_port}" ]]; then
            for ip in ${extra_ep4}; do
                get_vpn_ipv4_parts "${ip}" >/dev/null 2>&1 || continue
                printf '        ip daddr %s meta l4proto %s th dport %s accept\n' "${ip}" "${extra_transport}" "${extra_port}"
            done
            for ip in ${extra_ep6}; do
                get_vpn_v6_groups "${ip}" >/dev/null 2>&1 || continue
                printf '        ip6 daddr %s meta l4proto %s th dport %s accept\n' "${ip}" "${extra_transport}" "${extra_port}"
            done
        fi
        if [[ "${with_iface}" == "1" && "${iface}" =~ ^[a-zA-Z0-9_-]{1,15}$ ]]; then
            printf '        oifname "%s" meta nfproto ipv4 accept\n' "${iface}"
            if [[ "${v6}" == "1" ]]; then
                printf '        oifname "%s" meta nfproto ipv6 accept\n' "${iface}"
            fi
        fi
        printf '        limit rate 10/minute log prefix "w-vpn-drop "\n'
        printf '    }\n'
        printf '    chain ssh {\n'
        printf '        type route hook output priority %s; policy accept;\n' "${priority}"
        printf '        meta l4proto tcp th dport %s meta mark set %s\n' "${ssh_port}" "${mark}"
        printf '        meta l4proto tcp th sport %s meta mark set %s\n' "${ssh_port}" "${mark}"
        printf '    }\n'
        printf '}\n'
    } > "${tmp}"
    if ! nft -f "${tmp}"; then
        rm -f "${tmp}"
        return 1
    fi
    rm -f "${tmp}"
}

clear_vpn_killswitch() {
    command -v nft >/dev/null 2>&1 || return 0
    nft delete table inet w_vpn >/dev/null 2>&1 || true
}

check_vpn_flow() {
    local dst="$1" dport="$2"
    shift 2
    [[ "${dport}" == "67" || "${dport}" == "547" ]] && return 0
    [[ "${dst}" == "255.255.255.255" || "${dst}" == "ff02::1:2" ]] && return 0
    check_vpn_ip "${dst}" "$@"
}

clear_vpn_conntrack() {
    local line proto src dst sport dport
    local -a keep=()
    command -v conntrack >/dev/null 2>&1 || return 0
    mapfile -t keep < <(list_vpn_bypass)
    local name ep4 ep6 ip
    name="$(get_vpn_active 2>/dev/null || true)"
    if [[ -n "${1:-}" ]]; then
        name="$1"
    fi
    if [[ -n "${name}" ]]; then
        ep4="$(get_vpn_meta "${name}" endpoint4 2>/dev/null || true)"
        ep6="$(get_vpn_meta "${name}" endpoint6 2>/dev/null || true)"
        for ip in ${ep4} ${ep6}; do
            if [[ "${ip}" == *:* ]]; then
                keep+=("${ip}/128")
            else
                keep+=("${ip}/32")
            fi
        done
    fi
    while IFS= read -r line; do
        [[ "${line}" == *src=* && "${line}" == *dst=* ]] || continue
        proto="${line%% *}"
        src="${line#*src=}"
        src="${src%% *}"
        dst="${line#*dst=}"
        dst="${dst%% *}"
        sport="${line#*sport=}"
        sport="${sport%% *}"
        dport="${line#*dport=}"
        dport="${dport%% *}"
        [[ "${proto}" =~ ^(tcp|udp|icmp|icmpv6|sctp|dccp)$ ]] || continue
        [[ "${sport}" =~ ^[0-9]+$ && "${dport}" =~ ^[0-9]+$ ]] || continue
        if [[ "${sport}" == "$(get_vpn_ssh_port)" || "${dport}" == "$(get_vpn_ssh_port)" ]]; then
            continue
        fi
        if check_vpn_flow "${dst}" "${dport}" "${keep[@]}"; then
            continue
        fi
        conntrack -D -s "${src}" -d "${dst}" -p "${proto}" --sport "${sport}" --dport "${dport}" >/dev/null 2>&1 || true
    done < <(conntrack -L 2>/dev/null || true)
}

get_vpn_bypass_count() {
    local count=0 line
    if ! check_vpn_killswitch; then
        printf '0\n'
        return 0
    fi
    line="$(nft list set inet w_vpn bypass4 2>/dev/null || true)"
    line+="$(nft list set inet w_vpn bypass6 2>/dev/null || true)"
    count="$(printf '%s\n' "${line}" | grep -o '/' | wc -l | tr -d ' ')"
    printf '%s\n' "${count:-0}"
}
