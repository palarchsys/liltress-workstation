#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/killswitch.sh
# Updated at : 2026-11-16
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Close outbound traffic except the tunnel and the usual port.
# Note       : Saved exceptions and that port stay open.
# -----------------------------------------------------------------------------


# Commas separate the addresses inside one set.
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

# An empty set still names its address type.
render_vpn_nft_set() {
    local name="$1" kind="$2"
    shift 2
    if (($# == 0)); then
        printf '    set %s { type %s; flags interval; }\n' "${name}" "${kind}"
        return 0
    fi
    printf '    set %s { type %s; flags interval; elements = { %s } }\n' \
        "${name}" "${kind}" "$(collect_vpn_nft "$@")"
}

# A missing helper or a bad value keeps the usual port.
get_vpn_ssh_port() {
    local port="22"
    if declare -F get_ssh_port >/dev/null 2>&1; then
        get_ssh_port || true
        port="${SSH_PORT:-22}"
    fi
    [[ "${port}" =~ ^[0-9]+$ ]] || port="22"
    printf '%s\n' "${port}"
}

# The table exists only after a successful load.
check_vpn_killswitch() {
    command -v nft >/dev/null 2>&1 || return 1
    nft list table inet w_vpn >/dev/null 2>&1
}

# Saved exceptions come out one address on each line.
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
        done <"${applied}"
    fi
}

# A bad priority falls back to the built-in value.
read_vpn_nft_priority() {
    load_vpn_settings
    priority="${VPN_FW_PRIORITY:--150}"
    [[ "${priority}" =~ ^-[0-9]+$ ]] || priority=-150
}

# Each address is kept once. A colon means the long form.
collect_vpn_nft_bypass() {
    local cidr
    local -a cidrs=()
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
}

# The chosen profile supplies the interface and the peer.
read_vpn_nft_profile() {
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
}

# Only a well-formed peer address is kept.
collect_vpn_nft_endpoints() {
    local ip
    for ip in ${ep4}; do
        get_vpn_ipv4_parts "${ip}" >/dev/null 2>&1 || continue
        e4+=("${ip}")
    done
    for ip in ${ep6}; do
        get_vpn_v6_groups "${ip}" >/dev/null 2>&1 || continue
        e6+=("${ip}")
    done
}

# A second profile adds its own peer, when one was named.
read_vpn_nft_extra() {
    extra_transport=""
    extra_port=""
    extra_ep4=""
    extra_ep6=""
    if [[ -n "${extra}" ]]; then
        extra_transport="$(get_vpn_meta "${extra}" transport 2>/dev/null || true)"
        extra_port="$(get_vpn_meta "${extra}" port 2>/dev/null || true)"
        extra_ep4="$(get_vpn_meta "${extra}" endpoint4 2>/dev/null || true)"
        extra_ep6="$(get_vpn_meta "${extra}" endpoint6 2>/dev/null || true)"
        [[ "${extra_transport}" == "tcp" || "${extra_transport}" == "udp" ]] || extra_transport=""
        [[ "${extra_port}" =~ ^[0-9]+$ ]] || extra_port=""
    fi
}

# The packet tag is a number. An odd value falls back.
read_vpn_nft_mark() {
    ssh_port="$(get_vpn_ssh_port)"
    mark="${VPN_SSH_MARK:-17820}"
    [[ "${mark}" =~ ^[0-9]+$ ]] || mark=17820
}

# A missing peer still declares an empty set.
render_vpn_nft_endpoints() {
    if ((${#e4[@]} > 0)); then
        render_vpn_nft_set endpoint4 ipv4_addr "${e4[@]/%//32}"
    else
        render_vpn_nft_set endpoint4 ipv4_addr
    fi
    if ((${#e6[@]} > 0)); then
        render_vpn_nft_set endpoint6 ipv6_addr "${e6[@]/%//128}"
    else
        render_vpn_nft_set endpoint6 ipv6_addr
    fi
}

# Local traffic, exceptions, address setup, and the usual port stay open.
render_vpn_nft_output_head() {
    printf '    chain output {\n'
    printf '        type filter hook output priority %s; policy drop;\n' "${priority}"
    printf '        oifname "lo" accept\n'
    printf '        ip daddr @bypass4 accept\n'
    printf '        ip6 daddr @bypass6 accept\n'
    printf '        meta l4proto udp th sport 68 th dport 67 accept\n'
    printf '        meta l4proto udp th sport 546 th dport 547 accept\n'
    printf '        meta l4proto tcp th dport %s accept\n' "${ssh_port}"
    printf '        meta l4proto tcp th sport %s accept\n' "${ssh_port}"
}

# The peer port stays open on each saved address.
render_vpn_nft_profile_ports() {
    local ip
    if [[ -n "${transport}" && -n "${port}" ]]; then
        for ip in "${e4[@]}"; do
            printf '        ip daddr %s meta l4proto %s th dport %s accept\n' "${ip}" "${transport}" "${port}"
        done
        for ip in "${e6[@]}"; do
            printf '        ip6 daddr %s meta l4proto %s th dport %s accept\n' "${ip}" "${transport}" "${port}"
        done
    fi
}

# The second peer uses the same kind of opening.
render_vpn_nft_extra_ports() {
    local ip
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
}

# The tunnel interface is allowed only when the caller asks.
render_vpn_nft_iface() {
    if [[ "${with_iface}" == "1" && "${iface}" =~ ^[a-zA-Z0-9_-]{1,15}$ ]]; then
        printf '        oifname "%s" meta nfproto ipv4 accept\n' "${iface}"
        if [[ "${v6}" == "1" ]]; then
            printf '        oifname "%s" meta nfproto ipv6 accept\n' "${iface}"
        fi
    fi
}

# The tag chain keeps the usual port on its own route.
render_vpn_nft_tail() {
    printf '        limit rate 10/minute log prefix "w-vpn-drop "\n'
    printf '    }\n'
    printf '    chain ssh {\n'
    printf '        type route hook output priority %s; policy accept;\n' "${priority}"
    printf '        meta l4proto tcp th dport %s meta mark set %s\n' "${ssh_port}" "${mark}"
    printf '        meta l4proto tcp th sport %s meta mark set %s\n' "${ssh_port}" "${mark}"
    printf '    }\n'
    printf '}\n'
}

# The table drops outbound traffic the rules do not name.
apply_vpn_nft() {
    local name="${1:-}" with_iface="${2:-0}" extra="${3:-}"
    local home tmp iface proto port transport v6 ep4 ep6 ssh_port mark
    local extra_transport="" extra_port="" extra_ep4="" extra_ep6=""
    local -a b4=() b6=() e4=() e6=() cidrs=()
    local -A seen4=() seen6=()
    local cidr ip priority
    read_vpn_nft_priority
    home="$(get_vpn_home)"
    mkdir -p "${home}"
    collect_vpn_nft_bypass
    read_vpn_nft_profile
    collect_vpn_nft_endpoints
    read_vpn_nft_extra
    read_vpn_nft_mark
    tmp="$(mktemp "${home}/.nft.XXXXXX")"
    chmod 600 "${tmp}"
    {
        printf 'table inet w_vpn {\n'
        render_vpn_nft_set bypass4 ipv4_addr "${b4[@]}"
        render_vpn_nft_set bypass6 ipv6_addr "${b6[@]}"
        render_vpn_nft_endpoints
        render_vpn_nft_output_head
        render_vpn_nft_profile_ports
        render_vpn_nft_extra_ports
        render_vpn_nft_iface
        render_vpn_nft_tail
    } >"${tmp}"
    if ! nft -f "${tmp}"; then
        rm -f "${tmp}"
        return 1
    fi
    rm -f "${tmp}"
}

# Removing a missing table is not an error.
clear_vpn_killswitch() {
    command -v nft >/dev/null 2>&1 || return 0
    nft delete table inet w_vpn >/dev/null 2>&1 || true
}

# Address setup and the two broadcast targets stay.
check_vpn_flow() {
    local dst="$1" dport="$2"
    shift 2
    [[ "${dport}" == "67" || "${dport}" == "547" ]] && return 0
    [[ "${dst}" == "255.255.255.255" || "${dst}" == "ff02::1:2" ]] && return 0
    check_vpn_ip "${dst}" "$@"
}

# Bypass addresses and the active peer stay.
collect_vpn_conntrack_keep() {
    local name ip ep4 ep6
    mapfile -t keep < <(list_vpn_bypass)
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
}

# A row without both ends, or with an odd protocol, is ignored.
read_vpn_conntrack_fields() {
    local line="$1"
    [[ "${line}" == *src=* && "${line}" == *dst=* ]] || return 1
    proto="${line%% *}"
    src="${line#*src=}"
    src="${src%% *}"
    dst="${line#*dst=}"
    dst="${dst%% *}"
    sport="${line#*sport=}"
    sport="${sport%% *}"
    dport="${line#*dport=}"
    dport="${dport%% *}"
    [[ "${proto}" =~ ^(tcp|udp|icmp|icmpv6|sctp|dccp)$ ]] || return 1
    [[ "${sport}" =~ ^[0-9]+$ && "${dport}" =~ ^[0-9]+$ ]] || return 1
}

# The usual port is left in place on either side.
skip_vpn_conntrack_ssh() {
    if [[ "${sport}" == "$(get_vpn_ssh_port)" || "${dport}" == "$(get_vpn_ssh_port)" ]]; then
        return 0
    fi
    return 1
}

# An address the table allows is left in place.
skip_vpn_conntrack_flow() {
    if check_vpn_flow "${dst}" "${dport}" "$@"; then
        return 0
    fi
    return 1
}

# Live rows that are not an exception are removed.
clear_vpn_conntrack() {
    local line proto src dst sport dport
    local -a keep=()
    local name ep4 ep6 ip
    command -v conntrack >/dev/null 2>&1 || return 0
    collect_vpn_conntrack_keep "$@"
    while IFS= read -r line; do
        read_vpn_conntrack_fields "${line}" || continue
        skip_vpn_conntrack_ssh && continue
        skip_vpn_conntrack_flow "${keep[@]}" && continue
        conntrack -D -s "${src}" -d "${dst}" -p "${proto}" --sport "${sport}" --dport "${dport}" >/dev/null 2>&1 || true
    done < <(conntrack -L 2>/dev/null || true)
}

# The count is how many slashes the two sets contain.
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
