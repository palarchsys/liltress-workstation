#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/lib.sh
# Updated at : 2026-11-21
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Load VPN settings and answer profile questions.
# Note       : A refused bypass file leaves the previous set in place.
# -----------------------------------------------------------------------------


# The install tree when it is known, otherwise the tree that holds this script.
get_vpn_root() {
    if [[ -n "${INSTALL_DIRECTORY:-}" ]]; then
        printf '%s\n' "${INSTALL_DIRECTORY}"
        return 0
    fi
    local here
    here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    cd -- "${here}/../.." && pwd
}

# A deferred refresh waits. A missing helper is ignored.
refresh_vpn_integrity() {
    local script
    if [[ "${VPN_DEFER_INTEGRITY:-0}" == "1" ]]; then
        return 0
    fi
    script="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/refresh-integrity.sh"
    [[ -f "${script}" ]] || return 0
    bash "${script}"
}

# A watch row stays out. A private marker becomes the word secret.
strip_vpn_log_fields() {
    if [[ "${detail}" == *'BEGIN '* || "${detail}" == *PRIVATE* ]]; then
        detail="secret"
    fi
    detail="${detail//$'\t'/ }"
    detail="${detail//$'\n'/ }"
    name="${name//$'\t'/ }"
    name="${name//$'\n'/ }"
    result="${result//$'\t'/ }"
    result="${result//$'\n'/ }"
}

# The directory is mode 700. A missing tree restores the mask and stops quietly.
ensure_vpn_log_dir() {
    root="$(get_vpn_root 2>/dev/null)" || return 1
    [[ -n "${root}" ]] || return 1
    dir="${root}/log/vpn"
    old="$(umask)"
    umask 077
    mkdir -p "${dir}" 2>/dev/null || {
        umask "${old}"
        return 1
    }
    chmod 700 "${dir}" 2>/dev/null || true
}

# Append one daily row.
note_vpn_log() {
    local action="$1" name="${2:-}" result="${3:-}" detail="${4:-}"
    local root dir file stamp old
    [[ "${action}" == "watch" ]] && return 0
    strip_vpn_log_fields
    ensure_vpn_log_dir || return 0
    file="${dir}/$(date '+%Y-%m-%d').log"
    stamp="$(date '+%Y-%m-%dT%H:%M:%S.%N%z')"
    {
        if command -v flock >/dev/null 2>&1; then
            flock -w 2 9 || true
        fi
        printf '%s\t%s\t%s\t%s\t%s\n' "${stamp}" "${action}" "${name}" "${result}" "${detail}" >>"${file}" || true
    } 9>>"${dir}/day.lock"
    chmod 600 "${file}" 2>/dev/null || true
    umask "${old}"
    return 0
}

# Profiles live under the configured base.
get_vpn_home() {
    local base="${CONFIG_BASE_DIRECTORY:-/opt/liltress-workstation}"
    printf '%s/vpn\n' "${base}"
}

# Names that have a meta file, in byte order, one protocol at a time.
list_vpn_names() {
    local home dir name kind
    local -a found=()
    home="$(get_vpn_home)"
    [[ -d "${home}" ]] || return 0
    shopt -s nullglob
    for kind in wireguard openvpn profiles; do
        found=()
        for dir in "${home}/${kind}"/*/; do
            [[ -d "${dir}" ]] || continue
            name="$(basename -- "${dir}")"
            check_vpn_name "${name}" || continue
            [[ -f "${dir}meta" ]] || continue
            found+=("${name}")
        done
        if ((${#found[@]} > 0)); then
            printf '%s\n' "${found[@]}" | LC_ALL=C sort
        fi
    done
    shopt -u nullglob
}

# Names after the removed one, then names that came earlier.
list_vpn_successors() {
    local removed="$1" name started=0
    local -a names=() after=() before=()
    mapfile -t names < <(list_vpn_names)
    for name in "${names[@]}"; do
        if [[ "${name}" == "${removed}" ]]; then
            started=1
            continue
        fi
        if ((started == 1)); then
            after+=("${name}")
        else
            before+=("${name}")
        fi
    done
    if ((${#after[@]} > 0)); then
        printf '%s\n' "${after[@]}"
    fi
    if ((${#before[@]} > 0)); then
        printf '%s\n' "${before[@]}"
    fi
}

# How many profile directories exist.
count_vpn_profiles() {
    local home kind dir total=0
    home="$(get_vpn_home)"
    shopt -s nullglob
    for kind in wireguard openvpn profiles; do
        for dir in "${home}/${kind}"/*/; do
            [[ -d "${dir}" ]] || continue
            total=$((total + 1))
        done
    done
    shopt -u nullglob
    printf '%s\n' "${total}"
}

# Built-in values, applied again when a saved value is refused.
set_vpn_setting_defaults() {
    VPN_ON_BOOT=0
    VPN_BOOT_PROFILE=
    VPN_HANDSHAKE_TIMEOUT=25
    VPN_TABLE_ID=17820
    VPN_TABLE_NAME=w_vpn
    VPN_IFACE_WG=wg-liltress
    VPN_IFACE_OVPN=tun-liltress
    VPN_FW_PRIORITY=-150
    VPN_RULE_PRIO_ENDPOINT=40
    VPN_RULE_PRIO_BYPASS_TO=50
    VPN_RULE_PRIO_BYPASS_FROM=51
    VPN_RULE_PRIO_LAN=52
    VPN_RULE_PRIO_TUNNEL=100
    VPN_RULE_PRIO_SSH=45
    VPN_SSH_MARK=17820
    VPN_FAILOVER_TRIES=3
    VPN_FAILOVER_TIMEOUT=10
    VPN_TABLE_DIRECT_ID=17821
    VPN_TABLE_DIRECT_NAME=w_direct
    VPN_ROUTE_METRIC=50
    VPN_TUN_MTU=1200
}

# The profile file wins. The packaged file is the fallback.
read_vpn_setting_file() {
    local home file
    home="$(get_vpn_home)"
    file="${home}/vpn.conf"
    if [[ -f "${file}" ]]; then
        # shellcheck disable=SC1090
        source "${file}"
    elif [[ -f "$(get_vpn_root)/config/service/vpn/vpn.conf" ]]; then
        # shellcheck disable=SC1090
        source "$(get_vpn_root)/config/service/vpn/vpn.conf"
    fi
}

# Names, table numbers, and the handshake limit.
check_vpn_setting_ifaces() {
    [[ "${VPN_FW_PRIORITY}" =~ ^-[0-9]+$ ]] || VPN_FW_PRIORITY=-150
    [[ "${VPN_TABLE_ID}" =~ ^[0-9]+$ ]] || VPN_TABLE_ID=17820
    [[ "${VPN_TABLE_NAME}" =~ ^[a-z][a-z0-9_-]{0,14}$ ]] || VPN_TABLE_NAME=w_vpn
    [[ "${VPN_IFACE_WG}" =~ ^[a-zA-Z0-9_-]{1,15}$ ]] || VPN_IFACE_WG=wg-liltress
    [[ "${VPN_IFACE_OVPN}" =~ ^[a-zA-Z0-9_-]{1,15}$ ]] || VPN_IFACE_OVPN=tun-liltress
    [[ "${VPN_HANDSHAKE_TIMEOUT}" =~ ^[0-9]+$ ]] || VPN_HANDSHAKE_TIMEOUT=25
    [[ "${VPN_RULE_PRIO_ENDPOINT}" =~ ^[0-9]+$ ]] || VPN_RULE_PRIO_ENDPOINT=40
}

# Rule priorities and the failover limits.
check_vpn_setting_rules() {
    [[ "${VPN_RULE_PRIO_BYPASS_TO}" =~ ^[0-9]+$ ]] || VPN_RULE_PRIO_BYPASS_TO=50
    [[ "${VPN_RULE_PRIO_BYPASS_FROM}" =~ ^[0-9]+$ ]] || VPN_RULE_PRIO_BYPASS_FROM=51
    [[ "${VPN_RULE_PRIO_TUNNEL}" =~ ^[0-9]+$ ]] || VPN_RULE_PRIO_TUNNEL=100
    [[ "${VPN_RULE_PRIO_SSH}" =~ ^[0-9]+$ ]] || VPN_RULE_PRIO_SSH=45
    [[ "${VPN_SSH_MARK}" =~ ^[0-9]+$ ]] || VPN_SSH_MARK=17820
    [[ "${VPN_FAILOVER_TRIES}" =~ ^[1-9][0-9]*$ ]] || VPN_FAILOVER_TRIES=3
    [[ "${VPN_FAILOVER_TIMEOUT}" =~ ^[0-9]+$ ]] || VPN_FAILOVER_TIMEOUT=10
}

# The direct table and the route metric.
check_vpn_setting_direct() {
    [[ "${VPN_TABLE_DIRECT_ID}" =~ ^[0-9]+$ ]] || VPN_TABLE_DIRECT_ID=17821
    [[ "${VPN_TABLE_DIRECT_NAME}" =~ ^[a-z][a-z0-9_-]{0,14}$ ]] || VPN_TABLE_DIRECT_NAME=w_direct
    [[ "${VPN_ROUTE_METRIC}" =~ ^[0-9]+$ ]] || VPN_ROUTE_METRIC=50
    [[ "${VPN_TUN_MTU}" =~ ^[0-9]+$ ]] || VPN_TUN_MTU=1200
    [[ "${VPN_TUN_MTU}" -ge 576 && "${VPN_TUN_MTU}" -le 1500 ]] || VPN_TUN_MTU=1200
    [[ "${VPN_RULE_PRIO_LAN}" =~ ^[0-9]+$ ]] || VPN_RULE_PRIO_LAN=52
}

# Boot follows a valid default profile.
apply_vpn_setting_state() {
    if declare -F read_vpn_state >/dev/null 2>&1; then
        read_vpn_state
    else
        VPN_MODE=off
        VPN_ACTIVE=
        VPN_DEFAULT=
    fi
    VPN_ON_BOOT=0
    VPN_BOOT_PROFILE=
    if [[ -n "${VPN_DEFAULT:-}" ]] && declare -F check_vpn_profile_valid >/dev/null 2>&1; then
        if check_vpn_profile_valid "${VPN_DEFAULT}"; then
            VPN_ON_BOOT=1
            VPN_BOOT_PROFILE="${VPN_DEFAULT}"
        fi
    fi
}

# Defaults, then the saved file, then the limits, then boot.
load_vpn_settings() {
    set_vpn_setting_defaults
    read_vpn_setting_file
    check_vpn_setting_ifaces
    check_vpn_setting_rules
    check_vpn_setting_direct
    apply_vpn_setting_state
}

# A short lowercase name with digits and hyphens.
check_vpn_name() {
    [[ "${1:-}" =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]]
}

# The protocol directory when it is known, otherwise the first one that exists.
get_vpn_profile_dir() {
    local name="$1" proto="${2:-}" home candidate
    home="$(get_vpn_home)"
    if [[ "${proto}" == "wireguard" || "${proto}" == "openvpn" ]]; then
        printf '%s/%s/%s\n' "${home}" "${proto}" "${name}"
        return 0
    fi
    for candidate in wireguard openvpn profiles; do
        if [[ -d "${home}/${candidate}/${name}" ]]; then
            printf '%s/%s/%s\n' "${home}" "${candidate}" "${name}"
            return 0
        fi
    done
    printf '%s/wireguard/%s\n' "${home}" "${name}"
}

# Drop spaces at both ends. The value itself stays.
strip_vpn_text() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

# The catalog phrase when the catalog is present.
get_vpn_text() {
    local key="$1"
    shift
    if declare -F get_text >/dev/null 2>&1; then
        get_text "${key}" "$@"
        return 0
    fi
    printf '%s' "${key}"
}

# Show the catalog phrase on the error stream.
show_vpn_text_err() {
    printf '%s\n' "$(get_vpn_text "$@")" >&2
}

# The value stored beside that key.
get_vpn_meta() {
    local name="$1" key="$2" file line
    file="$(get_vpn_profile_dir "${name}")/meta"
    [[ -f "${file}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        case "${line}" in
            "${key}="*)
                printf '%s\n' "${line#"${key}="}"
                return 0
                ;;
        esac
    done <"${file}"
    return 1
}

# Store the profile fields and keep the file private.
write_vpn_meta() {
    local dir="$1" proto="$2" ep4="$3" ep6="$4" port="$5"
    local transport="$6" iface="$7" v6="$8" enc="$9" brand="${10:-}"
    umask 077
    cat >"${dir}/meta" <<EOF
proto=${proto}
endpoint4=${ep4}
endpoint6=${ep6}
port=${port}
transport=${transport}
iface=${iface}
has_ipv6=${v6}
encrypted=${enc}
brand=${brand}
EOF
    chmod 600 "${dir}/meta"
}

# The two halves of the key field name.
get_vpn_private_field() {
    printf '%s%s' 'Private' 'Key'
}

# Addresses that stay on the machine.
list_vpn_implicit() {
    printf '%s\n' '127.0.0.0/8' '::1/128' '169.254.0.0/16' 'fe80::/10'
}

# Explain a mask, a network, or a bad token.
fail_vpn_bypass() {
    local kind="$1" token="$2"
    case "${kind}" in
        mask)
            if declare -F get_text >/dev/null 2>&1; then
                show_vpn_text_err vpn.bypass.mask "${token}"
            else
                printf 'Mask required. Use the form 200.200.200.0/24. Line %s\n' "${token}" >&2
            fi
            ;;
        network)
            show_vpn_text_err vpn.bypass.network "${token}"
            ;;
        *)
            show_vpn_text_err vpn.bypass.bad "${token}"
            ;;
    esac
}

# Four dotted numbers, still unchecked against 255.
check_vpn_v4() {
    [[ "${1:-}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]
}

# One integer, or a refusal when an octet is too large.
get_vpn_ipv4_parts() {
    local addr="$1"
    [[ "${addr}" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
    local a b c d
    a=$((10#${BASH_REMATCH[1]}))
    b=$((10#${BASH_REMATCH[2]}))
    c=$((10#${BASH_REMATCH[3]}))
    d=$((10#${BASH_REMATCH[4]}))
    ((a <= 255 && b <= 255 && c <= 255 && d <= 255)) || return 1
    printf '%s\n' $(((a << 24) | (b << 16) | (c << 8) | d))
}

# An address and a prefix length of at most 32.
check_vpn_ipv4_syntax() {
    local cidr="$1" addr pref ip
    [[ "${cidr}" =~ ^([0-9.]+)/([0-9]+)$ ]] || return 1
    addr="${BASH_REMATCH[1]}"
    pref="${BASH_REMATCH[2]}"
    ((pref <= 32)) || return 1
    ip="$(get_vpn_ipv4_parts "${addr}")" || return 1
    printf '%s %s\n' "${ip}" "${pref}"
}

# Host bits must be zero.
check_vpn_ipv4_network() {
    local cidr="$1" parsed ip pref hostbits netmask
    parsed="$(check_vpn_ipv4_syntax "${cidr}")" || return 1
    ip="${parsed%% *}"
    pref="${parsed##* }"
    hostbits=$((32 - pref))
    if ((hostbits == 32)); then
        ((ip == 0)) || return 1
        return 0
    fi
    netmask=$(((0xFFFFFFFF << hostbits) & 0xFFFFFFFF))
    (((ip & netmask) == ip)) || return 1
}

# A zone suffix, a dotted tail, or two compressions are refused.
check_vpn_v6_shape() {
    local rest="${addr}"
    [[ "${addr}" == *%* || "${addr}" == *.* ]] && return 1
    [[ -z "${addr}" || "${addr}" == *:::* ]] && return 1
    doubles=0
    while [[ "${rest}" == *::* ]]; do
        doubles=$((doubles + 1))
        rest="${rest#*::}"
    done
    ((doubles <= 1)) || return 1
}

# Head and tail around one compression, or eight plain pieces.
split_vpn_v6_sides() {
    if ((doubles == 1)); then
        head="${addr%%::*}"
        tail="${addr#*::}"
    else
        head="${addr}"
        tail=""
    fi
    if [[ -n "${head}" ]]; then
        IFS=':' read -r -a left <<<"${head}"
    fi
    if [[ -n "${tail}" ]]; then
        IFS=':' read -r -a right <<<"${tail}"
    fi
    if ((doubles == 0 && ${#left[@]} != 8)); then
        return 1
    fi
}

# Compression must leave at least one empty piece.
check_vpn_v6_fill() {
    fill=$((8 - ${#left[@]} - ${#right[@]}))
    ((fill >= 0)) || return 1
    if ((doubles == 0 && fill != 0)); then
        return 1
    fi
    if ((doubles == 1 && fill < 1)); then
        return 1
    fi
}

# Each piece is at most four hex digits.
read_vpn_v6_pieces() {
    local piece
    for piece in "$@"; do
        [[ "${piece}" =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
        groups+=("$((16#${piece}))")
    done
}

# Empty pieces from compression become zero.
set_vpn_v6_zeros() {
    local index=0
    for ((index = 0; index < fill; index++)); do
        groups+=(0)
    done
}

# Eight numbers, or a refusal.
get_vpn_v6_groups() {
    local addr="$1" head="" tail=""
    local -a left=() right=() groups=()
    local fill=0 doubles=0
    check_vpn_v6_shape || return 1
    split_vpn_v6_sides || return 1
    check_vpn_v6_fill || return 1
    read_vpn_v6_pieces "${left[@]}" || return 1
    set_vpn_v6_zeros
    read_vpn_v6_pieces "${right[@]}" || return 1
    ((${#groups[@]} == 8)) || return 1
    printf '%s\n' "${groups[@]}"
}

# A prefix length of at most 128 and a valid address.
check_vpn_ipv6_syntax() {
    local cidr="$1" addr pref
    [[ "${cidr}" =~ ^([^/]+)/([0-9]+)$ ]] || return 1
    addr="${BASH_REMATCH[1]}"
    pref="${BASH_REMATCH[2]}"
    ((pref <= 128)) || return 1
    get_vpn_v6_groups "${addr}" >/dev/null || return 1
    printf '%s\n' "${pref}"
}

# One group must keep its host bits clear.
check_vpn_ipv6_group() {
    local value shift masked
    value="${groups[${index}]}"
    if ((index < full)); then
        return 0
    fi
    if ((index == full && rem > 0)); then
        shift=$((16 - rem))
        masked=$(((value >> shift) << shift))
        ((masked == value)) || return 1
        return 0
    fi
    ((value == 0)) || return 1
}

# Host bits beyond the prefix must be zero.
check_vpn_ipv6_network() {
    local cidr="$1" addr pref
    local -a groups=()
    local full rem index
    [[ "${cidr}" =~ ^([^/]+)/([0-9]+)$ ]] || return 1
    addr="${BASH_REMATCH[1]}"
    pref="${BASH_REMATCH[2]}"
    ((pref <= 128)) || return 1
    mapfile -t groups < <(get_vpn_v6_groups "${addr}") || return 1
    ((${#groups[@]} == 8)) || return 1
    full=$((pref / 16))
    rem=$((pref % 16))
    for ((index = 0; index < 8; index++)); do
        check_vpn_ipv6_group || return 1
    done
}

# An address without a prefix needs a mask. Anything else is a bad token.
check_vpn_cidr_mask() {
    if check_vpn_v4 "${token}" || get_vpn_v6_groups "${token}" >/dev/null 2>&1; then
        fail_vpn_bypass mask "${token}"
        return 1
    fi
    fail_vpn_bypass bad "${token}"
    return 1
}

# A v4 network, a v6 network, or a named refusal.
check_vpn_cidr() {
    local token="$1"
    if [[ "${token}" != */* ]]; then
        check_vpn_cidr_mask || return 1
    fi
    if [[ "${token}" != *:* ]]; then
        if check_vpn_ipv4_syntax "${token}" >/dev/null 2>&1; then
            if check_vpn_ipv4_network "${token}"; then
                return 0
            fi
            fail_vpn_bypass network "${token}"
            return 1
        fi
        fail_vpn_bypass bad "${token}"
        return 1
    fi
    if check_vpn_ipv6_syntax "${token}" >/dev/null 2>&1; then
        if check_vpn_ipv6_network "${token}"; then
            return 0
        fi
        fail_vpn_bypass network "${token}"
        return 1
    fi
    fail_vpn_bypass bad "${token}"
    return 1
}

# Blank rows and hash rows stay out.
skip_vpn_bypass_line() {
    line="${line%$'\r'}"
    trimmed="$(strip_vpn_text "${line}")"
    [[ -z "${trimmed}" || "${trimmed}" == \#* ]]
}

# A bracket cannot follow another row.
check_vpn_bypass_mix() {
    if ((bracket > 0 || plain > 0)); then
        fail_vpn_bypass bad "${trimmed}"
        return 1
    fi
}

# Keep the first sight of a token.
take_vpn_bypass_part() {
    local token
    token="$(strip_vpn_text "${part}")"
    [[ -n "${token}" ]] || {
        fail_vpn_bypass bad "${trimmed}"
        return 1
    }
    check_vpn_cidr "${token}" || return 1
    if [[ -z "${seen[${token}]+x}" ]]; then
        seen["${token}"]=1
        found+=("${token}")
    fi
}

# One bracket holds several tokens separated by commas.
read_vpn_bypass_bracket() {
    local inner part
    local -a parts=()
    check_vpn_bypass_mix || return 1
    [[ "${trimmed}" == *']' ]] || {
        fail_vpn_bypass bad "${trimmed}"
        return 1
    }
    bracket=1
    inner="${trimmed#[}"
    inner="${inner%]}"
    IFS=',' read -r -a parts <<<"${inner}"
    if ((${#parts[@]} == 0)); then
        fail_vpn_bypass bad "${trimmed}"
        return 1
    fi
    for part in "${parts[@]}"; do
        take_vpn_bypass_part || return 1
    done
}

# A plain row is refused once a bracket has been seen.
take_vpn_bypass_plain() {
    if ((bracket > 0)); then
        fail_vpn_bypass bad "${trimmed}"
        return 1
    fi
    plain=1
    check_vpn_cidr "${trimmed}" || return 1
    if [[ -z "${seen[${trimmed}]+x}" ]]; then
        seen["${trimmed}"]=1
        found+=("${trimmed}")
    fi
}

# Nothing to show leaves the output empty.
emit_vpn_bypass_found() {
    if ((${#found[@]} > 0)); then
        printf '%s\n' "${found[@]}"
    fi
}

# Bracket form or one token per row. Duplicates collapse.
read_vpn_bypass() {
    local file="$1" line trimmed
    local bracket=0 plain=0
    local -a found=()
    local -A seen=()
    [[ -f "${file}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        skip_vpn_bypass_line && continue
        if [[ "${trimmed}" == \[* ]]; then
            read_vpn_bypass_bracket || return 1
            continue
        fi
        take_vpn_bypass_plain || return 1
    done <"${file}"
    emit_vpn_bypass_found
    return 0
}

# A refused file leaves the previous set in place.
write_vpn_bypass() {
    local src="$1" dest="$2" dir tmp
    [[ -f "${src}" ]] || return 1
    dir="$(dirname -- "${dest}")"
    mkdir -p "${dir}" || return 1
    tmp="$(mktemp "${dir}/.bypass.XXXXXX")" || return 1
    if read_vpn_bypass "${src}" >"${tmp}"; then
        mv -f "${tmp}" "${dest}"
        return 0
    fi
    rm -f "${tmp}"
    return 1
}

# True when the address sits inside the network.
check_vpn_v4_cidr() {
    local ip="$1" cidr="$2" parsed value pref hostbits netmask network
    value="$(get_vpn_ipv4_parts "${ip}")" || return 1
    parsed="$(check_vpn_ipv4_syntax "${cidr}")" || return 1
    network="${parsed%% *}"
    pref="${parsed##* }"
    hostbits=$((32 - pref))
    if ((hostbits == 32)); then
        return 0
    fi
    netmask=$(((0xFFFFFFFF << hostbits) & 0xFFFFFFFF))
    (((value & netmask) == network))
}

# Compare one group, then the partial group at the prefix edge.
check_vpn_v6_group() {
    if ((index < full)); then
        ((left[index] == right[index])) || return 1
        return 0
    fi
    if ((index == full && rem > 0)); then
        local shift=$((16 - rem))
        (((left[index] >> shift) == (right[index] >> shift))) || return 1
    fi
}

# True when the address sits in the v6 network.
check_vpn_v6_cidr() {
    local ip="$1" cidr="$2" addr pref full rem index
    local -a left=() right=()
    addr="${cidr%/*}"
    pref="${cidr##*/}"
    mapfile -t left < <(get_vpn_v6_groups "${ip}") || return 1
    mapfile -t right < <(get_vpn_v6_groups "${addr}") || return 1
    full=$((pref / 16))
    rem=$((pref % 16))
    for ((index = 0; index < 8; index++)); do
        check_vpn_v6_group || return 1
    done
    return 0
}

# The first matching network wins.
check_vpn_ip() {
    local ip="$1" cidr
    local -a cidrs=("$@")
    cidrs=("${cidrs[@]:1}")
    for cidr in "${cidrs[@]}"; do
        if [[ "${ip}" == *:* ]]; then
            [[ "${cidr}" == *:* ]] || continue
            check_vpn_v6_cidr "${ip}" "${cidr}" && return 0
        else
            [[ "${cidr}" == *:* ]] && continue
            check_vpn_v4_cidr "${ip}" "${cidr}" && return 0
        fi
    done
    return 1
}

# The name recorded in the active file.
get_vpn_active() {
    local file
    file="$(get_vpn_home)/active"
    [[ -f "${file}" ]] || return 1
    tr -d '[:space:]' <"${file}"
}

# True when the saved mode is on.
check_vpn_mode() {
    [[ "${VPN_MODE:-off}" == "on" ]]
}

# True when a boot profile is saved.
check_vpn_boot_on() {
    [[ -n "${VPN_BOOT_PROFILE:-}" ]]
}

# A terminal or a graphical password box is enough.
check_vpn_passphrase() {
    [[ -t 0 ]] && return 0
    if [[ -n "${DISPLAY:-${WAYLAND_DISPLAY:-}}" ]] && command -v systemd-ask-password >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# True when the profile meta says the key is encrypted.
check_vpn_encrypted() {
    local name="$1" flag
    flag="$(get_vpn_meta "${name}" encrypted 2>/dev/null || true)"
    [[ "${flag}" == "1" ]]
}

# Hand the message to the alert sender when alerts are on.
send_vpn_alert() {
    local profile="$1" proto="$2" endpoint="$3" reason="$4"
    local send root
    [[ "${MAIL_ALERTS:-0}" == "1" ]] || return 0
    root="$(get_vpn_root)"
    send="${root}/service/cron/watchdogs/send.sh"
    [[ -f "${send}" ]] || return 0
    TITLE="$(get_vpn_text vpn.mail.title)"
    MODULE_NAME="$(get_vpn_text vpn.mail.module)"
    CONTENT="$(get_vpn_text vpn.mail.body "${profile}" "${proto}" "${endpoint}" "${reason}")"
    export TITLE MODULE_NAME CONTENT
    export BASE="${CONFIG_BASE_DIRECTORY:-/opt/liltress-workstation}"
    export PRODUCT_ROOT="${root}"
    bash "${send}" >/dev/null 2>&1 || true
}

# Rewrite the drop-in only when its text differs.
write_vpn_systemd_drop() {
    local drop="$1" body="$2" current=""
    if [[ -f "${drop}" ]]; then
        current="$(cat "${drop}")"
    fi
    if [[ "${current}" != "${body}" ]]; then
        if [[ -f "${drop}" ]] && declare -F copy_backup >/dev/null 2>&1; then
            copy_backup "${drop}"
        fi
        printf '%s\n' "${body}" >"${drop}"
        chmod 644 "${drop}"
    fi
}

# Disable the boot units and remove the ordering drop-in.
clear_vpn_systemd_boot() {
    local drop="$1"
    systemctl disable w-vpn-killswitch.service >/dev/null 2>&1 || true
    systemctl disable w-vpn.service >/dev/null 2>&1 || true
    rm -f "${drop}"
}

# The watch timer follows the saved mode.
apply_vpn_systemd_watch() {
    if check_vpn_mode; then
        systemctl enable --now w-vpn-watch.timer >/dev/null 2>&1 || return 1
        return 0
    fi
    systemctl disable --now w-vpn-watch.timer >/dev/null 2>&1 || true
}

# Boot units, then the watch timer, then a daemon reload.
apply_vpn_systemd() {
    local drop="/etc/systemd/system/w-boot-chain.service.d/vpn.conf" body
    load_vpn_settings
    if [[ "${VPN_ON_BOOT}" == "1" ]]; then
        systemctl enable w-vpn-killswitch.service >/dev/null 2>&1 || return 1
        systemctl enable w-vpn.service >/dev/null 2>&1 || return 1
        install -d -m 755 /etc/systemd/system/w-boot-chain.service.d
        body="$(printf '%s\n' '[Unit]' 'After=w-vpn.service')"
        write_vpn_systemd_drop "${drop}" "${body}"
    else
        clear_vpn_systemd_boot "${drop}"
    fi
    apply_vpn_systemd_watch || return 1
    systemctl daemon-reload >/dev/null 2>&1 || true
}

# The active name, from memory or from the active file.
read_vpn_verify_name() {
    name="${VPN_ACTIVE}"
    if [[ -z "${name}" ]]; then
        name="$(get_vpn_active 2>/dev/null || true)"
    fi
    [[ -n "${name}" ]]
}

# The interface must exist on the machine.
check_vpn_verify_iface() {
    iface="$(get_vpn_meta "${name}" iface 2>/dev/null || true)"
    proto="$(get_vpn_meta "${name}" proto 2>/dev/null || true)"
    [[ -n "${iface}" ]] && ip link show "${iface}" >/dev/null 2>&1
}

# A recent handshake is ok. A missing or old one is stale.
read_vpn_verify_wg() {
    local now age
    now="$(date +%s)"
    age="$(wg show "${iface}" latest-handshakes 2>/dev/null | awk -F '[\t ]+' 'NF {print $NF; exit}')"
    if [[ ! "${age}" =~ ^[0-9]+$ || "${age}" -eq 0 ]]; then
        printf 'stale %s\n' "${name}"
        return 0
    fi
    if ((now - age > VPN_HANDSHAKE_TIMEOUT)); then
        printf 'stale %s\n' "${name}"
        return 0
    fi
    printf 'ok %s\n' "${name}"
}

# The handshake file uses the same age limit.
read_vpn_verify_stamp() {
    local stamp now age
    stamp="$(get_vpn_profile_dir "${name}")/handshake"
    if [[ ! -f "${stamp}" ]]; then
        printf 'stale %s\n' "${name}"
        return 0
    fi
    now="$(date +%s)"
    age="$(tr -d '[:space:]' <"${stamp}")"
    if [[ ! "${age}" =~ ^[0-9]+$ ]] || ((now - age > VPN_HANDSHAKE_TIMEOUT)); then
        printf 'stale %s\n' "${name}"
        return 0
    fi
    printf 'ok %s\n' "${name}"
}

# off, down, stale, or ok.
get_vpn_verify_state() {
    local name iface proto
    load_vpn_settings
    if ! check_vpn_mode; then
        printf 'off\n'
        return 0
    fi
    if ! read_vpn_verify_name; then
        printf 'down\n'
        return 0
    fi
    if ! check_vpn_verify_iface; then
        printf 'down %s\n' "${name}"
        return 0
    fi
    if [[ "${proto}" == "wireguard" ]] && command -v wg >/dev/null 2>&1; then
        read_vpn_verify_wg
        return 0
    fi
    read_vpn_verify_stamp
}
