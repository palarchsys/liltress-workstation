#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/lib.sh
# Updated at : 2026-11-14
# Creator    : palarchsys
# =============================================================================

get_vpn_root() {
    if [[ -n "${INSTALL_DIRECTORY:-}" ]]; then
        printf '%s\n' "${INSTALL_DIRECTORY}"
        return 0
    fi
    local here
    here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    cd -- "${here}/../.." && pwd
}

note_vpn_log() {
    local action="$1" name="${2:-}" result="${3:-}" detail="${4:-}"
    local root dir file stamp old
    [[ "${action}" == "watch" ]] && return 0
    if [[ "${detail}" == *'BEGIN '* || "${detail}" == *PRIVATE* ]]; then
        detail="secret"
    fi
    detail="${detail//$'\t'/ }"
    detail="${detail//$'\n'/ }"
    name="${name//$'\t'/ }"
    name="${name//$'\n'/ }"
    result="${result//$'\t'/ }"
    result="${result//$'\n'/ }"
    root="$(get_vpn_root 2>/dev/null)" || return 0
    [[ -n "${root}" ]] || return 0
    dir="${root}/log/vpn"
    old="$(umask)"
    umask 077
    mkdir -p "${dir}" 2>/dev/null || { umask "${old}"; return 0; }
    chmod 700 "${dir}" 2>/dev/null || true
    file="${dir}/$(date '+%Y-%m-%d').log"
    stamp="$(date '+%Y-%m-%dT%H:%M:%S.%N%z')"
    {
        if command -v flock >/dev/null 2>&1; then
            flock -w 2 9 || true
        fi
        printf '%s\t%s\t%s\t%s\t%s\n' "${stamp}" "${action}" "${name}" "${result}" "${detail}" >> "${file}" || true
    } 9>>"${dir}/day.lock"
    chmod 600 "${file}" 2>/dev/null || true
    umask "${old}"
    return 0
}

get_vpn_home() {
    local base="${CONFIG_BASE_DIRECTORY:-/opt/liltress-workstation}"
    printf '%s/vpn\n' "${base}"
}

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

load_vpn_settings() {
    local home file
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
    VPN_RULE_PRIO_TUNNEL=100
    VPN_RULE_PRIO_SSH=45
    VPN_SSH_MARK=17820
    VPN_FAILOVER_TRIES=3
    VPN_FAILOVER_TIMEOUT=10
    VPN_TABLE_DIRECT_ID=17821
    VPN_TABLE_DIRECT_NAME=w_direct
    VPN_ROUTE_METRIC=50
    home="$(get_vpn_home)"
    file="${home}/vpn.conf"
    if [[ -f "${file}" ]]; then
        # shellcheck disable=SC1090
        source "${file}"
    elif [[ -f "$(get_vpn_root)/config/vpn/vpn.conf" ]]; then
        # shellcheck disable=SC1090
        source "$(get_vpn_root)/config/vpn/vpn.conf"
    fi
    [[ "${VPN_FW_PRIORITY}" =~ ^-[0-9]+$ ]] || VPN_FW_PRIORITY=-150
    [[ "${VPN_TABLE_ID}" =~ ^[0-9]+$ ]] || VPN_TABLE_ID=17820
    [[ "${VPN_TABLE_NAME}" =~ ^[a-z][a-z0-9_-]{0,14}$ ]] || VPN_TABLE_NAME=w_vpn
    [[ "${VPN_IFACE_WG}" =~ ^[a-zA-Z0-9_-]{1,15}$ ]] || VPN_IFACE_WG=wg-liltress
    [[ "${VPN_IFACE_OVPN}" =~ ^[a-zA-Z0-9_-]{1,15}$ ]] || VPN_IFACE_OVPN=tun-liltress
    [[ "${VPN_HANDSHAKE_TIMEOUT}" =~ ^[0-9]+$ ]] || VPN_HANDSHAKE_TIMEOUT=25
    [[ "${VPN_RULE_PRIO_ENDPOINT}" =~ ^[0-9]+$ ]] || VPN_RULE_PRIO_ENDPOINT=40
    [[ "${VPN_RULE_PRIO_BYPASS_TO}" =~ ^[0-9]+$ ]] || VPN_RULE_PRIO_BYPASS_TO=50
    [[ "${VPN_RULE_PRIO_BYPASS_FROM}" =~ ^[0-9]+$ ]] || VPN_RULE_PRIO_BYPASS_FROM=51
    [[ "${VPN_RULE_PRIO_TUNNEL}" =~ ^[0-9]+$ ]] || VPN_RULE_PRIO_TUNNEL=100
    [[ "${VPN_RULE_PRIO_SSH}" =~ ^[0-9]+$ ]] || VPN_RULE_PRIO_SSH=45
    [[ "${VPN_SSH_MARK}" =~ ^[0-9]+$ ]] || VPN_SSH_MARK=17820
    [[ "${VPN_FAILOVER_TRIES}" =~ ^[1-9][0-9]*$ ]] || VPN_FAILOVER_TRIES=3
    [[ "${VPN_FAILOVER_TIMEOUT}" =~ ^[0-9]+$ ]] || VPN_FAILOVER_TIMEOUT=10
    [[ "${VPN_TABLE_DIRECT_ID}" =~ ^[0-9]+$ ]] || VPN_TABLE_DIRECT_ID=17821
    [[ "${VPN_TABLE_DIRECT_NAME}" =~ ^[a-z][a-z0-9_-]{0,14}$ ]] || VPN_TABLE_DIRECT_NAME=w_direct
    [[ "${VPN_ROUTE_METRIC}" =~ ^[0-9]+$ ]] || VPN_ROUTE_METRIC=50
    if declare -F read_vpn_state >/dev/null 2>&1; then
        read_vpn_state
    else
        VPN_MODE=off
        VPN_ACTIVE=
    fi
    if [[ "${VPN_MODE}" == "on" ]]; then
        VPN_ON_BOOT=1
    else
        VPN_ON_BOOT=0
    fi
    VPN_BOOT_PROFILE="${VPN_ACTIVE}"
}

check_vpn_name() {
    [[ "${1:-}" =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]]
}

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

strip_vpn_text() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

get_vpn_text() {
    local key="$1"
    shift
    if declare -F get_text >/dev/null 2>&1; then
        get_text "${key}" "$@"
        return 0
    fi
    printf '%s' "${key}"
}

show_vpn_text_err() {
    printf '%s\n' "$(get_vpn_text "$@")" >&2
}

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
    done < "${file}"
    return 1
}

write_vpn_meta() {
    local dir="$1" proto="$2" ep4="$3" ep6="$4" port="$5"
    local transport="$6" iface="$7" v6="$8" enc="$9" brand="${10:-}"
    umask 077
    cat > "${dir}/meta" << EOF
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

get_vpn_private_field() {
    printf '%s%s' 'Private' 'Key'
}

list_vpn_implicit() {
    printf '%s\n' '127.0.0.0/8' '::1/128' '169.254.0.0/16' 'fe80::/10'
}

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

check_vpn_v4() {
    [[ "${1:-}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]
}

get_vpn_ipv4_parts() {
    local addr="$1"
    [[ "${addr}" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
    local a b c d
    a=$((10#${BASH_REMATCH[1]}))
    b=$((10#${BASH_REMATCH[2]}))
    c=$((10#${BASH_REMATCH[3]}))
    d=$((10#${BASH_REMATCH[4]}))
    (( a <= 255 && b <= 255 && c <= 255 && d <= 255 )) || return 1
    printf '%s\n' $(( (a << 24) | (b << 16) | (c << 8) | d ))
}

check_vpn_ipv4_syntax() {
    local cidr="$1" addr pref ip
    [[ "${cidr}" =~ ^([0-9.]+)/([0-9]+)$ ]] || return 1
    addr="${BASH_REMATCH[1]}"
    pref="${BASH_REMATCH[2]}"
    (( pref <= 32 )) || return 1
    ip="$(get_vpn_ipv4_parts "${addr}")" || return 1
    printf '%s %s\n' "${ip}" "${pref}"
}

check_vpn_ipv4_network() {
    local cidr="$1" parsed ip pref hostbits netmask
    parsed="$(check_vpn_ipv4_syntax "${cidr}")" || return 1
    ip="${parsed%% *}"
    pref="${parsed##* }"
    hostbits=$((32 - pref))
    if (( hostbits == 32 )); then
        (( ip == 0 )) || return 1
        return 0
    fi
    netmask=$(( (0xFFFFFFFF << hostbits) & 0xFFFFFFFF ))
    (( (ip & netmask) == ip )) || return 1
}

get_vpn_v6_groups() {
    local addr="$1" head tail piece
    local -a left=() right=() groups=()
    local fill=0 index=0
    [[ "${addr}" == *%* || "${addr}" == *.* ]] && return 1
    [[ -z "${addr}" || "${addr}" == *:::* ]] && return 1
    local doubles=0 rest="${addr}"
    while [[ "${rest}" == *::* ]]; do
        doubles=$((doubles + 1))
        rest="${rest#*::}"
    done
    (( doubles <= 1 )) || return 1
    if (( doubles == 1 )); then
        head="${addr%%::*}"
        tail="${addr#*::}"
    else
        head="${addr}"
        tail=""
    fi
    if [[ -n "${head}" ]]; then
        IFS=':' read -r -a left <<< "${head}"
    fi
    if [[ -n "${tail}" ]]; then
        IFS=':' read -r -a right <<< "${tail}"
    fi
    if (( doubles == 0 && ${#left[@]} != 8 )); then
        return 1
    fi
    fill=$((8 - ${#left[@]} - ${#right[@]}))
    (( fill >= 0 )) || return 1
    if (( doubles == 0 && fill != 0 )); then
        return 1
    fi
    if (( doubles == 1 && fill < 1 )); then
        return 1
    fi
    for piece in "${left[@]}"; do
        [[ "${piece}" =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
        groups+=("$((16#${piece}))")
    done
    for (( index=0; index<fill; index++ )); do
        groups+=(0)
    done
    for piece in "${right[@]}"; do
        [[ "${piece}" =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
        groups+=("$((16#${piece}))")
    done
    (( ${#groups[@]} == 8 )) || return 1
    printf '%s\n' "${groups[@]}"
}

check_vpn_ipv6_syntax() {
    local cidr="$1" addr pref
    [[ "${cidr}" =~ ^([^/]+)/([0-9]+)$ ]] || return 1
    addr="${BASH_REMATCH[1]}"
    pref="${BASH_REMATCH[2]}"
    (( pref <= 128 )) || return 1
    get_vpn_v6_groups "${addr}" >/dev/null || return 1
    printf '%s\n' "${pref}"
}

check_vpn_ipv6_network() {
    local cidr="$1" addr pref piece
    local -a groups=()
    [[ "${cidr}" =~ ^([^/]+)/([0-9]+)$ ]] || return 1
    addr="${BASH_REMATCH[1]}"
    pref="${BASH_REMATCH[2]}"
    (( pref <= 128 )) || return 1
    mapfile -t groups < <(get_vpn_v6_groups "${addr}") || return 1
    (( ${#groups[@]} == 8 )) || return 1
    local full=$((pref / 16)) rem=$((pref % 16)) index=0 value=0 shift=0 masked=0
    for (( index=0; index<8; index++ )); do
        value="${groups[${index}]}"
        if (( index < full )); then
            continue
        fi
        if (( index == full && rem > 0 )); then
            shift=$((16 - rem))
            masked=$(( (value >> shift) << shift ))
            (( masked == value )) || return 1
        else
            (( value == 0 )) || return 1
        fi
    done
}

check_vpn_cidr() {
    local token="$1"
    if [[ "${token}" != */* ]]; then
        if check_vpn_v4 "${token}" || get_vpn_v6_groups "${token}" >/dev/null 2>&1; then
            fail_vpn_bypass mask "${token}"
            return 1
        fi
        fail_vpn_bypass bad "${token}"
        return 1
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

read_vpn_bypass() {
    local file="$1" line trimmed token part inner
    local bracket=0 plain=0
    local -a found=() parts=()
    local -A seen=()
    [[ -f "${file}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        trimmed="$(strip_vpn_text "${line}")"
        [[ -z "${trimmed}" || "${trimmed}" == \#* ]] && continue
        if [[ "${trimmed}" == \[* ]]; then
            if (( bracket > 0 || plain > 0 )); then
                fail_vpn_bypass bad "${trimmed}"
                return 1
            fi
            [[ "${trimmed}" == *\] ]] || {
                fail_vpn_bypass bad "${trimmed}"
                return 1
            }
            bracket=1
            inner="${trimmed#[}"
            inner="${inner%]}"
            IFS=',' read -r -a parts <<< "${inner}"
            if (( ${#parts[@]} == 0 )); then
                fail_vpn_bypass bad "${trimmed}"
                return 1
            fi
            for part in "${parts[@]}"; do
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
            done
            continue
        fi
        if (( bracket > 0 )); then
            fail_vpn_bypass bad "${trimmed}"
            return 1
        fi
        plain=1
        check_vpn_cidr "${trimmed}" || return 1
        if [[ -z "${seen[${trimmed}]+x}" ]]; then
            seen["${trimmed}"]=1
            found+=("${trimmed}")
        fi
    done < "${file}"
    if (( ${#found[@]} > 0 )); then
        printf '%s\n' "${found[@]}"
    fi
    return 0
}

# A refused file leaves the previous set in place.
write_vpn_bypass() {
    local src="$1" dest="$2" dir tmp
    [[ -f "${src}" ]] || return 1
    dir="$(dirname -- "${dest}")"
    mkdir -p "${dir}" || return 1
    tmp="$(mktemp "${dir}/.bypass.XXXXXX")" || return 1
    if read_vpn_bypass "${src}" > "${tmp}"; then
        mv -f "${tmp}" "${dest}"
        return 0
    fi
    rm -f "${tmp}"
    return 1
}

check_vpn_v4_cidr() {
    local ip="$1" cidr="$2" parsed value pref hostbits netmask network
    value="$(get_vpn_ipv4_parts "${ip}")" || return 1
    parsed="$(check_vpn_ipv4_syntax "${cidr}")" || return 1
    network="${parsed%% *}"
    pref="${parsed##* }"
    hostbits=$((32 - pref))
    if (( hostbits == 32 )); then
        return 0
    fi
    netmask=$(( (0xFFFFFFFF << hostbits) & 0xFFFFFFFF ))
    (( (value & netmask) == network ))
}

check_vpn_v6_cidr() {
    local ip="$1" cidr="$2" addr pref
    local -a left=() right=()
    addr="${cidr%/*}"
    pref="${cidr##*/}"
    mapfile -t left < <(get_vpn_v6_groups "${ip}") || return 1
    mapfile -t right < <(get_vpn_v6_groups "${addr}") || return 1
    local full=$((pref / 16)) rem=$((pref % 16)) index=0 shift=0
    for (( index=0; index<8; index++ )); do
        if (( index < full )); then
            (( left[index] == right[index] )) || return 1
            continue
        fi
        if (( index == full && rem > 0 )); then
            shift=$((16 - rem))
            (( (left[index] >> shift) == (right[index] >> shift) )) || return 1
        fi
    done
    return 0
}

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

get_vpn_active() {
    local file
    file="$(get_vpn_home)/active"
    [[ -f "${file}" ]] || return 1
    tr -d '[:space:]' < "${file}"
}

check_vpn_mode() {
    [[ "${VPN_MODE:-off}" == "on" ]]
}

check_vpn_boot_on() {
    check_vpn_mode
}

check_vpn_passphrase() {
    [[ -t 0 ]] && return 0
    if [[ -n "${DISPLAY:-${WAYLAND_DISPLAY:-}}" ]] && command -v systemd-ask-password >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

check_vpn_encrypted() {
    local name="$1" flag
    flag="$(get_vpn_meta "${name}" encrypted 2>/dev/null || true)"
    [[ "${flag}" == "1" ]]
}

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

apply_vpn_systemd() {
    local drop="/etc/systemd/system/w-boot-chain.service.d/vpn.conf"
    load_vpn_settings
    if [[ "${VPN_ON_BOOT}" == "1" ]]; then
        systemctl enable w-vpn-killswitch.service >/dev/null 2>&1 || return 1
        systemctl enable w-vpn.service >/dev/null 2>&1 || return 1
        systemctl enable --now w-vpn-watch.timer >/dev/null 2>&1 || return 1
        install -d -m 755 /etc/systemd/system/w-boot-chain.service.d
        if [[ -f "${drop}" ]] && declare -F copy_backup >/dev/null 2>&1; then
            copy_backup "${drop}"
        fi
        cat > "${drop}" << 'EOF'
[Unit]
After=w-vpn.service
EOF
        chmod 644 "${drop}"
    else
        systemctl disable w-vpn-killswitch.service >/dev/null 2>&1 || true
        systemctl disable w-vpn.service >/dev/null 2>&1 || true
        systemctl disable --now w-vpn-watch.timer >/dev/null 2>&1 || true
        rm -f "${drop}"
    fi
    systemctl daemon-reload >/dev/null 2>&1 || true
}

get_vpn_verify_state() {
    local name iface proto stamp now age
    load_vpn_settings
    if ! check_vpn_mode; then
        printf 'off\n'
        return 0
    fi
    name="${VPN_ACTIVE}"
    if [[ -z "${name}" ]]; then
        name="$(get_vpn_active 2>/dev/null || true)"
    fi
    if [[ -z "${name}" ]]; then
        printf 'down\n'
        return 0
    fi
    iface="$(get_vpn_meta "${name}" iface 2>/dev/null || true)"
    proto="$(get_vpn_meta "${name}" proto 2>/dev/null || true)"
    if [[ -z "${iface}" ]] || ! ip link show "${iface}" >/dev/null 2>&1; then
        printf 'down %s\n' "${name}"
        return 0
    fi
    if [[ "${proto}" == "wireguard" ]] && command -v wg >/dev/null 2>&1; then
        now="$(date +%s)"
        age="$(wg show "${iface}" latest-handshakes 2>/dev/null | awk -F '[\t ]+' 'NF {print $NF; exit}')"
        if [[ ! "${age}" =~ ^[0-9]+$ || "${age}" -eq 0 ]]; then
            printf 'stale %s\n' "${name}"
            return 0
        fi
        if (( now - age > VPN_HANDSHAKE_TIMEOUT )); then
            printf 'stale %s\n' "${name}"
            return 0
        fi
        printf 'ok %s\n' "${name}"
        return 0
    fi
    stamp="$(get_vpn_profile_dir "${name}")/handshake"
    if [[ ! -f "${stamp}" ]]; then
        printf 'stale %s\n' "${name}"
        return 0
    fi
    now="$(date +%s)"
    age="$(tr -d '[:space:]' < "${stamp}")"
    if [[ ! "${age}" =~ ^[0-9]+$ ]] || (( now - age > VPN_HANDSHAKE_TIMEOUT )); then
        printf 'stale %s\n' "${name}"
        return 0
    fi
    printf 'ok %s\n' "${name}"
}
