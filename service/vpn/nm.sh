#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/nm.sh
# Updated at : 2026-11-21
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Build NetworkManager profiles and follow link events.
# Note       : A held counter keeps a switch from turning the tunnel off.
# -----------------------------------------------------------------------------


# Saved file name of one profile.
vpn_nm_connection_path() {
    local name="$1" dir
    dir="${VPN_NM_DIR:-/etc/NetworkManager/system-connections}"
    printf '%s/liltress-%s.nmconnection\n' "${dir}" "${name}"
}

# Profile name taken from that file name.
vpn_nm_name_of() {
    local base
    base="$(basename -- "$1")"
    base="${base#liltress-}"
    base="${base%.nmconnection}"
    printf '%s\n' "${base}"
}

# Counter file that pauses link events.
vpn_nm_hold_path() {
    printf '%s/nm.hold\n' "$(get_vpn_home)"
}

# Stamp file used during a profile change.
vpn_nm_switch_path() {
    printf '%s/nm.switch\n' "$(get_vpn_home)"
}

# Create that stamp with a private mode.
vpn_nm_stamp_on() {
    local file old
    file="$1"
    mkdir -p "$(dirname -- "${file}")"
    old="$(umask)"
    umask 077
    printf '1\n' >"${file}"
    umask "${old}"
    chmod 600 "${file}"
}

# Raise the pause counter by one.
vpn_nm_hold_on() {
    local file count old
    file="$(vpn_nm_hold_path)"
    mkdir -p "$(dirname -- "${file}")"
    if [[ -f "${file}" ]]; then
        count="$(tr -d '[:space:]' <"${file}")"
        [[ "${count}" =~ ^[0-9]+$ ]] || count=0
        count=$((count + 1))
    else
        count=1
    fi
    old="$(umask)"
    umask 077
    printf '%s\n' "${count}" >"${file}"
    umask "${old}"
    chmod 600 "${file}"
}

# Lower the pause counter, or delete it at one.
vpn_nm_hold_off() {
    local file count old
    file="$(vpn_nm_hold_path)"
    [[ -f "${file}" ]] || return 0
    count="$(tr -d '[:space:]' <"${file}")"
    [[ "${count}" =~ ^[0-9]+$ ]] || count=1
    if [[ "${count}" -le 1 ]]; then
        rm -f -- "${file}"
        return 0
    fi
    count=$((count - 1))
    old="$(umask)"
    umask 077
    printf '%s\n' "${count}" >"${file}"
    umask "${old}"
    chmod 600 "${file}"
}

# True when the pause counter file exists.
vpn_nm_held() {
    [[ -f "$(vpn_nm_hold_path)" ]]
}

# Remember that a profile change is under way.
vpn_nm_switch_on() {
    vpn_nm_stamp_on "$(vpn_nm_switch_path)"
}

# Clear the profile-change stamp.
vpn_nm_switch_off() {
    rm -f "$(vpn_nm_switch_path)"
}

# True when a profile change is under way.
vpn_nm_switching() {
    [[ -f "$(vpn_nm_switch_path)" ]]
}

# True when this profile may start at boot.
vpn_nm_wants_auto() {
    local name="$1" active chosen
    if [[ "${VPN_NM_AUTOCONNECT:-}" == "0" ]]; then
        return 1
    fi
    if declare -F load_vpn_settings >/dev/null 2>&1; then
        load_vpn_settings
    fi
    chosen="${VPN_BOOT_PROFILE:-}"
    [[ -n "${chosen}" && "${chosen}" == "${name}" ]] || return 1
    active="$(get_vpn_active 2>/dev/null || true)"
    [[ -z "${active}" || "${active}" == "${name}" ]]
}

# Boot choice that is idle, or already this name, may start.
check_vpn_nm_boot() {
    local name="$1" chosen="$2" active="$3"
    if [[ -n "${chosen}" && "${name}" == "${chosen}" ]]; then
        if [[ -z "${active}" || "${active}" == "${name}" ]]; then
            return 0
        fi
    fi
    return 1
}

# Each saved profile gets the boot choice above.
vpn_nm_apply_autoconnect() {
    local name active chosen want
    if declare -F load_vpn_settings >/dev/null 2>&1; then
        load_vpn_settings
    fi
    chosen="${VPN_BOOT_PROFILE:-}"
    active="$(get_vpn_active 2>/dev/null || true)"
    while IFS= read -r name; do
        [[ -n "${name}" ]] || continue
        want="false"
        check_vpn_nm_boot "${name}" "${chosen}" "${active}" && want="true"
        vpn_nm_set_autoconnect "${name}" "${want}" || true
    done < <(vpn_nm_each)
}

# Drop quotes and outer space from one field.
vpn_nm_token() {
    local raw="$1"
    raw="$(strip_vpn_text "${raw}")"
    raw="${raw#\"}"
    raw="${raw%\"}"
    raw="${raw#\'}"
    raw="${raw%\'}"
    printf '%s' "${raw}"
}

# Absolute path, or the profile directory plus a relative one.
vpn_nm_abs() {
    local dir="$1" token="$2"
    token="$(vpn_nm_token "${token}")"
    [[ -n "${token}" ]] || return 1
    if [[ "${token}" == /* ]]; then
        printf '%s\n' "${token}"
        return 0
    fi
    printf '%s/%s\n' "${dir}" "${token}"
}

# First word of the remainder of a line.
vpn_nm_first() {
    local rest="$1"
    rest="$(strip_vpn_text "${rest}")"
    [[ -n "${rest}" ]] || return 1
    printf '%s\n' "${rest%%[[:space:]]*}"
}

# Keep an existing id, or make a fresh one.
vpn_nm_uuid() {
    local path="$1" line
    if [[ -f "${path}" ]]; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            case "${line}" in
                uuid=*)
                    printf '%s\n' "${line#uuid=}"
                    return 0
                    ;;
            esac
        done <"${path}"
    fi
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        tr -d '[:space:]' </proc/sys/kernel/random/uuid
        return 0
    fi
    printf '%s\n' "11111111-1111-4111-8111-111111111111"
}

# First line is the user. Second line is the secret.
vpn_nm_auth_pair() {
    local file="$1" line n=0
    [[ -f "${file}" && ! -L "${file}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        n=$((n + 1))
        if ((n == 1)); then
            printf '%s\n' "$(strip_vpn_text "${line}")"
        elif ((n == 2)); then
            printf '%s\n' "${line}"
            return 0
        fi
    done <"${file}"
    return 1
}

# Endpoint, port, and tunnel name come from the profile meta.
read_vpn_nm_openvpn_meta() {
    local name="$1"
    dir="$(get_vpn_profile_dir "${name}")"
    runtime="${dir}/runtime"
    [[ -f "${runtime}" ]] || return 1
    load_vpn_settings
    iface="$(get_vpn_meta "${name}" iface 2>/dev/null || true)"
    [[ -n "${iface}" ]] || iface="${VPN_IFACE_OVPN}"
    transport="$(get_vpn_meta "${name}" transport 2>/dev/null || true)"
    port="$(get_vpn_meta "${name}" port 2>/dev/null || true)"
    remote="$(get_vpn_meta "${name}" endpoint4 2>/dev/null || true)"
    [[ -n "${remote}" ]] || remote="$(get_vpn_meta "${name}" endpoint6 2>/dev/null || true)"
    remote="${remote%% *}"
    v6="$(get_vpn_meta "${name}" has_ipv6 2>/dev/null || echo 0)"
    enc="$(get_vpn_meta "${name}" encrypted 2>/dev/null || echo 0)"
    [[ -n "${remote}" && "${port}" =~ ^[0-9]+$ ]] || return 1
}

# Remember a certificate path from the runtime.
read_vpn_nm_openvpn_file() {
    local dir="$1" key="$2" val="$3"
    case "${key}" in
        ca)
            ca="$(vpn_nm_abs "${dir}" "${val}")" || true
            ;;
        cert)
            cert="$(vpn_nm_abs "${dir}" "${val}")" || true
            ;;
        key)
            keyf="$(vpn_nm_abs "${dir}" "${val}")" || true
            ;;
    esac
}

# Remember where the user secret lives.
read_vpn_nm_openvpn_auth() {
    local dir="$1" val="$2"
    if [[ -n "${val}" ]]; then
        auth="$(vpn_nm_abs "${dir}" "${val}")" || true
    else
        auth="${dir}/auth.txt"
    fi
}

# Remember extra TLS material from the runtime.
read_vpn_nm_openvpn_tls() {
    local dir="$1" key="$2" val="$3" rest="$4"
    case "${key}" in
        remote-cert-tls)
            rcert="$(vpn_nm_token "${val}")"
            ;;
        tls-crypt)
            tcrypt="$(vpn_nm_abs "${dir}" "${val}")" || true
            ;;
        tls-crypt-v2)
            tcrypt2="$(vpn_nm_abs "${dir}" "${val}")" || true
            ;;
        tls-auth)
            ta="$(vpn_nm_abs "${dir}" "${val}")" || true
            tadir="$(strip_vpn_text "${rest#"${val}"}")"
            tadir="${tadir%%[[:space:]]*}"
            ;;
    esac
}

# One runtime line. A blank or a hash line is skipped.
read_vpn_nm_openvpn_line() {
    local dir="$1" line trimmed key rest val
    line="${2%$'\r'}"
    trimmed="$(strip_vpn_text "${line}")"
    [[ -z "${trimmed}" || "${trimmed}" == \#* || "${trimmed}" == \;* ]] && return 1
    key="${trimmed%%[[:space:]]*}"
    rest="$(strip_vpn_text "${trimmed#"${key}"}")"
    val="$(vpn_nm_first "${rest}" 2>/dev/null || true)"
    case "${key}" in
        ca | cert | key)
            read_vpn_nm_openvpn_file "${dir}" "${key}" "${val}"
            ;;
        auth-user-pass)
            read_vpn_nm_openvpn_auth "${dir}" "${val}"
            ;;
        remote-cert-tls | tls-crypt | tls-crypt-v2 | tls-auth)
            read_vpn_nm_openvpn_tls "${dir}" "${key}" "${val}" "${rest}"
            ;;
    esac
}

# Fill the user and the secret when that file exists.
read_vpn_nm_openvpn_secret() {
    local dir="$1"
    if [[ -z "${auth}" && -f "${dir}/auth.txt" ]]; then
        auth="${dir}/auth.txt"
    fi
    if [[ -n "${auth}" && -f "${auth}" ]]; then
        user="$(vpn_nm_auth_pair "${auth}" | sed -n '1p')"
        password="$(vpn_nm_auth_pair "${auth}" | sed -n '2p')"
    fi
}

# True when both a certificate and a secret are present.
check_vpn_nm_openvpn_pair() {
    [[ -n "${cert}" && -n "${keyf}" && -n "${user}" && -n "${password}" ]]
}

# Pick password, certificate, or both.
read_vpn_nm_openvpn_kind() {
    if check_vpn_nm_openvpn_pair; then
        kind="password-tls"
    elif [[ -n "${user}" && -n "${password}" ]]; then
        kind="password"
    elif [[ -n "${cert}" && -n "${keyf}" ]]; then
        kind="tls"
    else
        return 1
    fi
}

# Boot flag, transport, and the stable id.
read_vpn_nm_openvpn_flags() {
    local name="$1" path="$2"
    if vpn_nm_wants_auto "${name}"; then
        auto="true"
    else
        auto="false"
    fi
    uuid="$(vpn_nm_uuid "${path}")"
    if [[ "${transport}" == "tcp" ]]; then
        tcp="yes"
    else
        tcp="no"
    fi
}

# Connection block of the saved profile.
render_vpn_nm_openvpn_link() {
    printf '%s\n' '[connection]'
    printf 'id=%s\n' "${name}"
    printf 'uuid=%s\n' "${uuid}"
    printf '%s\n' 'type=vpn'
    printf 'interface-name=%s\n' "${iface}"
    printf 'autoconnect=%s\n' "${auto}"
    printf '%s\n' 'permissions='
    printf '\n'
}

# OpenVPN block, including optional certificate lines.
render_vpn_nm_openvpn_vpn() {
    printf '%s\n' '[vpn]'
    printf '%s\n' 'service-type=org.freedesktop.NetworkManager.openvpn'
    printf 'connection-type=%s\n' "${kind}"
    printf 'ca=%s\n' "${ca}"
    if [[ -n "${cert}" ]]; then
        printf 'cert=%s\n' "${cert}"
    fi
    if [[ -n "${keyf}" ]]; then
        printf 'key=%s\n' "${keyf}"
    fi
    if [[ "${enc}" == "1" ]]; then
        printf '%s\n' 'cert-pass-flags=1'
    fi
    printf 'remote=%s\n' "${remote}"
    printf 'port=%s\n' "${port}"
    printf 'proto-tcp=%s\n' "${tcp}"
    printf 'dev=%s\n' "${iface}"
    printf '%s\n' 'dev-type=tun'
}

# Optional TLS lines after the device type.
render_vpn_nm_openvpn_extra() {
    if [[ -n "${rcert}" ]]; then
        printf 'remote-cert-tls=%s\n' "${rcert}"
    fi
    if [[ -n "${ta}" ]]; then
        printf 'ta=%s\n' "${ta}"
        [[ "${tadir}" == "0" || "${tadir}" == "1" ]] || tadir="1"
        printf 'ta-dir=%s\n' "${tadir}"
    fi
    if [[ -n "${tcrypt}" ]]; then
        printf 'tls-crypt=%s\n' "${tcrypt}"
    fi
    if [[ -n "${tcrypt2}" ]]; then
        printf 'tls-crypt-v2=%s\n' "${tcrypt2}"
    fi
}

# User, secret flag, and the secret block.
render_vpn_nm_openvpn_login() {
    if [[ -n "${user}" ]]; then
        printf 'username=%s\n' "${user}"
    fi
    if [[ -n "${password}" ]]; then
        printf '%s\n' 'password-flags=0'
    fi
    printf '\n'
    if [[ -n "${password}" ]]; then
        printf '%s\n' '[vpn-secrets]'
        printf 'password=%s\n' "${password}"
        printf '\n'
    fi
}

# Address blocks and the profile stamp.
render_vpn_nm_openvpn_net() {
    printf '%s\n' '[ipv4]'
    printf '%s\n' 'method=auto'
    printf '%s\n' 'ignore-auto-dns=true'
    printf '%s\n' 'never-default=false'
    printf 'route-metric=%s\n' "${VPN_ROUTE_METRIC}"
    printf '\n'
    printf '%s\n' '[ipv6]'
    printf '%s\n' 'ignore-auto-dns=true'
    if [[ "${v6}" == "1" ]]; then
        printf '%s\n' 'method=auto'
        printf '%s\n' 'never-default=false'
        printf 'route-metric=%s\n' "${VPN_ROUTE_METRIC}"
    else
        printf '%s\n' 'method=disabled'
        printf '%s\n' 'never-default=true'
    fi
    printf '\n'
    printf '%s\n' '[user]'
    printf 'liltress.profile=%s\n' "${name}"
}

# Build an OpenVPN profile from the runtime file.
vpn_nm_render_openvpn() {
    local name="$1" path="$2" dir runtime iface transport port remote v6
    local line trimmed key rest val ca="" cert="" keyf="" auth="" user="" password=""
    local rcert="" ta="" tadir="" tcrypt="" tcrypt2="" kind auto uuid tcp enc
    read_vpn_nm_openvpn_meta "${name}" || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        read_vpn_nm_openvpn_line "${dir}" "${line}" || continue
    done <"${runtime}"
    [[ -n "${ca}" ]] || return 1
    read_vpn_nm_openvpn_secret "${dir}"
    read_vpn_nm_openvpn_kind || return 1
    read_vpn_nm_openvpn_flags "${name}" "${path}"
    {
        render_vpn_nm_openvpn_link
        render_vpn_nm_openvpn_vpn
        render_vpn_nm_openvpn_extra
        render_vpn_nm_openvpn_login
        render_vpn_nm_openvpn_net
    } >"${path}"
    chmod 600 "${path}"
}

# One peer block, with a wide allowed range.
vpn_nm_peer_block() {
    local key="$1" endpoint="$2" keep="$3" psk="$4"
    printf '[wireguard-peer.%s]\n' "${key}"
    printf 'public-key=%s\n' "${key}"
    if [[ -n "${endpoint}" ]]; then
        printf 'endpoint=%s\n' "${endpoint}"
    fi
    printf '%s\n' 'allowed-ips=0.0.0.0/0;::/0;'
    if [[ -n "${keep}" ]]; then
        printf 'persistent-keepalive=%s\n' "${keep}"
    fi
    if [[ -n "${psk}" ]]; then
        printf 'preshared-key=%s\n' "${psk}"
    fi
    printf '\n'
}

# Tunnel name and the private-field label.
read_vpn_nm_wireguard_meta() {
    local name="$1"
    dir="$(get_vpn_profile_dir "${name}")"
    runtime="${dir}/runtime"
    [[ -f "${runtime}" ]] || return 1
    load_vpn_settings
    iface="$(get_vpn_meta "${name}" iface 2>/dev/null || true)"
    [[ -n "${iface}" ]] || iface="${VPN_IFACE_WG}"
    v6="$(get_vpn_meta "${name}" has_ipv6 2>/dev/null || echo 0)"
    field="$(get_vpn_private_field)"
}

# Append the current peer when one is complete.
read_vpn_nm_wireguard_peer() {
    if [[ "${section}" == "Peer" && -n "${pubkey}" ]]; then
        peers="${peers}$(vpn_nm_peer_block "${pubkey}" "${endpoint}" "${keep}" "${psk}")"
    fi
}

# Close the previous peer and start the next section.
read_vpn_nm_wireguard_header() {
    local trimmed="$1"
    read_vpn_nm_wireguard_peer
    section="${trimmed#[}"
    section="${section%]}"
    pubkey=""
    endpoint=""
    keep=""
    psk=""
}

# Keep the private value from the interface section.
read_vpn_nm_wireguard_iface() {
    local key="$1" val="$2"
    if [[ "${section}" == "Interface" && "${key}" == "${field}" ]]; then
        private="${val}"
    fi
}

# Keep peer fields from the peer section.
read_vpn_nm_wireguard_peer_key() {
    local key="$1" val="$2"
    [[ "${section}" != "Peer" ]] && return 0
    if [[ "${key}" == "PublicKey" ]]; then
        pubkey="${val}"
    elif [[ "${key}" == "Endpoint" ]]; then
        endpoint="${val}"
    elif [[ "${key}" == "PersistentKeepalive" ]]; then
        keep="${val}"
    elif [[ "${key}" == "PresharedKey" ]]; then
        psk="${val}"
    fi
}

# A blank or a hash line does not carry a field.
skip_vpn_nm_wireguard_line() {
    local trimmed="$1"
    [[ -z "${trimmed}" || "${trimmed}" == \#* ]]
}

# A profile needs a private value and at least one peer.
require_vpn_nm_wireguard() {
    [[ -n "${private}" && -n "${peers}" ]]
}

# Separate addresses into v4 and v6 lines.
read_vpn_nm_wireguard_addrs() {
    local addr
    if declare -F list_vpn_wg_addresses >/dev/null 2>&1; then
        while IFS= read -r addr; do
            [[ -n "${addr}" ]] || continue
            if [[ "${addr}" == *:* ]]; then
                n6=$((n6 + 1))
                v6text="${v6text}address${n6}=${addr}"$'\n'
            else
                n4=$((n4 + 1))
                v4text="${v4text}address${n4}=${addr}"$'\n'
            fi
        done < <(list_vpn_wg_addresses "${runtime}")
    fi
}

# Boot flag and the stable id.
read_vpn_nm_wireguard_auto() {
    local name="$1" path="$2"
    if vpn_nm_wants_auto "${name}"; then
        auto="true"
    else
        auto="false"
    fi
    uuid="$(vpn_nm_uuid "${path}")"
}

# Connection block and the private value.
render_vpn_nm_wireguard_head() {
    printf '%s\n' '[connection]'
    printf 'id=%s\n' "${name}"
    printf 'uuid=%s\n' "${uuid}"
    printf '%s\n' 'type=wireguard'
    printf 'interface-name=%s\n' "${iface}"
    printf 'autoconnect=%s\n' "${auto}"
    printf '%s\n' 'permissions='
    printf '\n'
    printf '%s\n' '[wireguard]'
    printf 'private-key=%s\n' "${private}"
    printf '\n'
    printf '%s\n' "${peers}"
}

# IPv4 method follows the address count.
render_vpn_nm_wireguard_ipv4() {
    printf '%s\n' '[ipv4]'
    if ((n4 > 0)); then
        printf '%s\n' 'method=manual'
        printf '%s' "${v4text}"
    else
        printf '%s\n' 'method=disabled'
    fi
    printf '%s\n' 'ignore-auto-dns=true'
    printf '%s\n' 'never-default=false'
    printf 'route-metric=%s\n' "${VPN_ROUTE_METRIC}"
    printf '\n'
}

# IPv6 method follows the address count and the meta flag.
render_vpn_nm_wireguard_ipv6() {
    printf '%s\n' '[ipv6]'
    printf '%s\n' 'ignore-auto-dns=true'
    if ((n6 > 0)); then
        printf '%s\n' 'method=manual'
        printf '%s' "${v6text}"
    elif [[ "${v6}" == "1" ]]; then
        printf '%s\n' 'method=auto'
    else
        printf '%s\n' 'method=disabled'
    fi
    if [[ "${v6}" == "1" ]]; then
        printf '%s\n' 'never-default=false'
        printf 'route-metric=%s\n' "${VPN_ROUTE_METRIC}"
    else
        printf '%s\n' 'never-default=true'
    fi
    printf '\n'
    printf '%s\n' '[user]'
    printf 'liltress.profile=%s\n' "${name}"
}

# Build a WireGuard profile from the runtime file.
vpn_nm_render_wireguard() {
    local name="$1" path="$2" dir runtime iface v6 line trimmed section=""
    local key rest val field private="" pubkey="" endpoint="" keep="" psk=""
    local peers="" auto uuid addr n4=0 n6=0 v4text="" v6text=""
    read_vpn_nm_wireguard_meta "${name}" || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        trimmed="$(strip_vpn_text "${line}")"
        if [[ "${trimmed}" == \[*\] ]]; then
            read_vpn_nm_wireguard_header "${trimmed}"
            continue
        fi
        skip_vpn_nm_wireguard_line "${trimmed}" && continue
        key="$(strip_vpn_text "${trimmed%%=*}")"
        rest="$(strip_vpn_text "${trimmed#*=}")"
        val="${rest}"
        read_vpn_nm_wireguard_iface "${key}" "${val}"
        read_vpn_nm_wireguard_peer_key "${key}" "${val}"
    done <"${runtime}"
    read_vpn_nm_wireguard_peer
    require_vpn_nm_wireguard || return 1
    read_vpn_nm_wireguard_addrs
    read_vpn_nm_wireguard_auto "${name}" "${path}"
    {
        render_vpn_nm_wireguard_head
        render_vpn_nm_wireguard_ipv4
        render_vpn_nm_wireguard_ipv6
    } >"${path}"
    chmod 600 "${path}"
}

# WireGuard and OpenVPN use different builders.
render_vpn_nm_connection() {
    local name="$1" path="$2" proto
    proto="$(get_vpn_meta "${name}" proto 2>/dev/null || true)"
    if [[ "${proto}" == "wireguard" ]]; then
        vpn_nm_render_wireguard "${name}" "${path}"
        return
    fi
    vpn_nm_render_openvpn "${name}" "${path}"
}

# Store the profile, then tell the daemon when it is the system one.
install_vpn_nm_connection() {
    local name="$1" path dir
    path="$(vpn_nm_connection_path "${name}")"
    dir="$(dirname -- "${path}")"
    if [[ -n "${VPN_NM_DIR:-}" ]]; then
        install -d -m 700 "${dir}"
    else
        install -d -m 755 "${dir}"
    fi
    render_vpn_nm_connection "${name}" "${path}" || return 1
    chmod 600 "${path}"
    if [[ -z "${VPN_NM_DIR:-}" ]] && command -v nmcli >/dev/null 2>&1; then
        nmcli connection load "${path}" >/dev/null 2>&1 || return 1
    fi
}

# Only true, yes, and 1 stay true.
read_vpn_nm_autoconnect_want() {
    local raw="$1"
    if [[ "${raw}" == "true" || "${raw}" == "yes" || "${raw}" == "1" ]]; then
        want="true"
    else
        want="false"
    fi
}

# A new section may need the flag on the previous one.
read_vpn_nm_autoconnect_head() {
    local line="$1"
    if [[ "${section}" == "[connection]" && "${seen}" -eq 0 ]]; then
        printf 'autoconnect=%s\n' "${want}" >>"${tmp}"
        seen=1
    fi
    section="${line}"
    printf '%s\n' "${line}" >>"${tmp}"
}

# Replace an existing flag. Other lines stay.
read_vpn_nm_autoconnect_row() {
    local line="$1"
    if [[ "${section}" == "[connection]" && "${line}" == autoconnect=* ]]; then
        printf 'autoconnect=%s\n' "${want}" >>"${tmp}"
        seen=1
        return 0
    fi
    printf '%s\n' "${line}" >>"${tmp}"
    return 1
}

# A connection block at the end still needs the flag.
read_vpn_nm_autoconnect_tail() {
    if [[ "${section}" == "[connection]" && "${seen}" -eq 0 ]]; then
        printf 'autoconnect=%s\n' "${want}" >>"${tmp}"
    fi
}

# The daemon hears the same flag when profiles are system-wide.
apply_vpn_nm_autoconnect_live() {
    local name="$1"
    if [[ -z "${VPN_NM_DIR:-}" ]] && command -v nmcli >/dev/null 2>&1; then
        if [[ "${want}" == "true" ]]; then
            nmcli connection modify id "${name}" connection.autoconnect yes >/dev/null 2>&1 || true
        else
            nmcli connection modify id "${name}" connection.autoconnect no >/dev/null 2>&1 || true
        fi
    fi
}

# Change the boot flag inside one saved profile.
vpn_nm_set_autoconnect() {
    local name="$1" want="$2" file tmp line section="" seen=0
    read_vpn_nm_autoconnect_want "${want}"
    file="$(vpn_nm_connection_path "${name}")"
    [[ -f "${file}" ]] || return 1
    tmp="$(mktemp "${file}.XXXXXX")"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == \[*\] ]]; then
            read_vpn_nm_autoconnect_head "${line}"
            continue
        fi
        read_vpn_nm_autoconnect_row "${line}" && continue
    done <"${file}"
    read_vpn_nm_autoconnect_tail
    cat "${tmp}" >"${file}"
    rm -f "${tmp}"
    chmod 600 "${file}"
    apply_vpn_nm_autoconnect_live "${name}"
}

# Each saved profile name, one per line.
vpn_nm_each() {
    local file name dir glob
    dir="${VPN_NM_DIR:-/etc/NetworkManager/system-connections}"
    [[ -d "${dir}" ]] || return 0
    glob="$(shopt -p nullglob)"
    shopt -s nullglob
    for file in "${dir}"/liltress-*.nmconnection; do
        name="$(vpn_nm_name_of "${file}")"
        [[ -n "${name}" ]] || continue
        printf '%s\n' "${name}"
    done
    eval "${glob}"
}

# Same boot flag on every saved profile.
vpn_nm_autoconnect_all() {
    local want="$1" name
    while IFS= read -r name; do
        [[ -n "${name}" ]] || continue
        vpn_nm_set_autoconnect "${name}" "${want}" || true
    done < <(vpn_nm_each)
}

# Bring other profiles down, leaving one up.
stop_vpn_nm_others() {
    local keep="$1" name
    command -v nmcli >/dev/null 2>&1 || return 0
    [[ -z "${VPN_NM_DIR:-}" ]] || return 0
    while IFS= read -r name; do
        [[ -n "${name}" ]] || continue
        [[ "${name}" == "${keep}" ]] && continue
        nmcli connection down id "${name}" >/dev/null 2>&1 || true
    done < <(vpn_nm_each)
}

# Bring every saved profile down.
stop_vpn_nm_all() {
    stop_vpn_nm_others ""
}

# Delete the daemon entry, then the saved file.
remove_vpn_nm_connection() {
    local name="$1" path nested=0
    path="$(vpn_nm_connection_path "${name}")"
    if [[ -z "${VPN_NM_DIR:-}" ]] && command -v nmcli >/dev/null 2>&1; then
        if ! vpn_nm_held; then
            vpn_nm_hold_on
            nested=1
        fi
        nmcli connection delete id "${name}" >/dev/null 2>&1 || true
        if ((nested == 1)); then
            vpn_nm_hold_off
        fi
    fi
    rm -f "${path}"
}

# True when the daemon reports that profile as up.
vpn_nm_activated() {
    local name="$1" state
    [[ -z "${VPN_NM_DIR:-}" ]] || return 1
    command -v nmcli >/dev/null 2>&1 || return 1
    state="$(timeout 2 nmcli -g GENERAL.STATE connection show id "${name}" 2>/dev/null || true)"
    [[ "${state}" == activated* ]]
}

# True when any saved profile is up.
vpn_nm_any_up() {
    local name
    while IFS= read -r name; do
        [[ -n "${name}" ]] || continue
        if vpn_nm_activated "${name}"; then
            return 0
        fi
    done < <(vpn_nm_each)
    return 1
}

# Pause until that profile is up, or the deadline passes.
wait_vpn_nm() {
    local name="$1" deadline
    deadline=$((SECONDS + VPN_HANDSHAKE_TIMEOUT))
    while ((SECONDS <= deadline)); do
        if vpn_nm_activated "${name}"; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# Ask the daemon to bring that profile up.
vpn_nm_up() {
    local name="$1"
    [[ -z "${VPN_NM_DIR:-}" ]] || return 1
    command -v nmcli >/dev/null 2>&1 || return 1
    nmcli -w "${VPN_HANDSHAKE_TIMEOUT}" connection up id "${name}" >/dev/null 2>&1
}

# Leave the tunnel device outside the daemon.
vpn_nm_unmanage() {
    local iface="$1"
    [[ -n "${iface}" ]] || return 0
    [[ -z "${VPN_NM_DIR:-}" ]] || return 0
    command -v nmcli >/dev/null 2>&1 || return 0
    nmcli device set "${iface}" managed no >/dev/null 2>&1 || true
}

# Remember the active profile name.
vpn_nm_set_active() {
    local name="$1" file
    if declare -F set_vpn_active >/dev/null 2>&1; then
        set_vpn_active "${name}"
        return 0
    fi
    file="$(get_vpn_home)/active"
    printf '%s\n' "${name}" >"${file}"
    chmod 600 "${file}"
}

# Prepare routes before the tunnel comes up.
apply_vpn_link_setup() {
    local name="$1"
    if ! install_vpn_nm_connection "${name}"; then
        rc=1
        VPN_NM_FAULT="load"
    elif ! stop_vpn_nm_others "${name}"; then
        rc=1
    elif ! remember_vpn_direct_route; then
        rc=1
    elif ! apply_vpn_endpoint_routes "${name}"; then
        rc=1
    elif ! apply_vpn_bypass_routes; then
        rc=1
    fi
}

# Open the tunnel once those routes are ready.
apply_vpn_link_tunnel() {
    local name="$1"
    ((rc == 0)) || return 0
    if ! apply_vpn_ssh; then
        rc=1
    elif ! apply_vpn_nft "${name}" 0; then
        rc=1
    elif ! vpn_nm_up "${name}"; then
        rc=1
        VPN_NM_FAULT="up"
    elif ! wait_vpn_nm "${name}"; then
        rc=1
        VPN_NM_FAULT="up"
    fi
}

# After the tunnel is up, routes and boot flags follow.
finish_vpn_link_up() {
    local name="$1"
    clear_vpn_tunnel_routes || true
    apply_vpn_nft "${name}" 1 || rc=1
    vpn_nm_apply_autoconnect || true
}

# A failed attempt turns the boot flag off and drops the link.
finish_vpn_link_down() {
    local name="$1"
    vpn_nm_set_autoconnect "${name}" false || true
    if [[ -z "${VPN_NM_DIR:-}" ]] && command -v nmcli >/dev/null 2>&1; then
        nmcli connection down id "${name}" >/dev/null 2>&1 || true
    fi
}

# Bring one profile up, and undo it when a step fails.
raise_vpn_link() {
    local name="$1" rc=0
    VPN_NM_FAULT=""
    vpn_nm_hold_on
    apply_vpn_link_setup "${name}"
    apply_vpn_link_tunnel "${name}"
    if ((rc == 0)); then
        finish_vpn_link_up "${name}"
    else
        finish_vpn_link_down "${name}"
    fi
    vpn_nm_hold_off
    return "${rc}"
}

# Profile stamp on this line, when the line carries one.
read_vpn_nm_profile_value() {
    local line="$1"
    case "${line}" in
        data=*liltress.profile=*)
            value="${line#*liltress.profile=}"
            value="${value%%;*}"
            value="$(strip_vpn_text "${value}")"
            return 0
            ;;
        liltress.profile=*)
            value="$(strip_vpn_text "${line#liltress.profile=}")"
            return 0
            ;;
    esac
    return 1
}

# Profile name stored in a saved connection file.
vpn_nm_profile_mark() {
    local file="${1:-}" line value=""
    [[ -n "${file}" && -f "${file}" && ! -L "${file}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        read_vpn_nm_profile_value "${line}" || continue
        [[ -n "${value}" ]] || return 1
        printf '%s\n' "${value}"
        return 0
    done <"${file}"
    return 1
}

# Turn the tunnel off without a daemon event.
quiet_vpn_down() {
    vpn_nm_hold_on
    set_vpn_state_mode off
    load_vpn_settings
    apply_vpn_systemd || true
    clear_vpn_network
    restart_vpn_services || true
    note_vpn_log mode-off "-" ok "nm"
    vpn_nm_hold_off
    if declare -F refresh_vpn_integrity >/dev/null 2>&1; then
        refresh_vpn_integrity || true
    fi
}

# Up and down events need a profile stamp.
read_vpn_nm_event_profile() {
    local action="$1"
    case "${action}" in
        vpn-pre-up | vpn-up | vpn-down | vpn-pre-down)
            profile="$(vpn_nm_profile_mark "${CONNECTION_FILENAME:-}" 2>/dev/null || true)"
            [[ -n "${profile}" ]] || return 1
            ;;
    esac
    return 0
}

# Routes and the filter go in before the tunnel exists.
apply_vpn_nm_pre_up() {
    local profile="$1"
    set_vpn_state_mode on
    load_vpn_settings
    apply_vpn_systemd || true
    remember_vpn_direct_route || true
    apply_vpn_ssh || true
    apply_vpn_endpoint_routes "${profile}" || true
    apply_vpn_bypass_routes || true
    apply_vpn_nft "${profile}" 0 || true
}

# 1228-byte packets passed. 1400-byte packets did not.
apply_vpn_tunnel_mtu() {
    local profile="$1" iface
    load_vpn_settings
    iface="$(get_vpn_meta "${profile}" iface 2>/dev/null || true)"
    [[ -n "${iface}" ]] || return 0
    ip link show "${iface}" >/dev/null 2>&1 || return 0
    ip link set dev "${iface}" mtu "${VPN_TUN_MTU}" >/dev/null 2>&1 || true
}

# The tunnel is up, so the active name and the filter follow.
apply_vpn_nm_up() {
    local profile="$1"
    set_vpn_state_mode on
    apply_vpn_tunnel_mtu "${profile}"
    clear_vpn_tunnel_routes || true
    vpn_nm_set_active "${profile}"
    set_vpn_state_active "${profile}" || true
    record_vpn_attempt "${profile}" 1 || true
    apply_vpn_nft "${profile}" 1 || true
    restart_vpn_services || true
    note_vpn_log mode-on "${profile}" ok "nm"
    if declare -F refresh_vpn_integrity >/dev/null 2>&1; then
        refresh_vpn_integrity || true
    fi
}

# Turn the tunnel off when no other profile remains.
apply_vpn_nm_down() {
    if vpn_nm_switching || vpn_nm_any_up; then
        return 0
    fi
    quiet_vpn_down
}

# The killswitch must learn the new local prefix while the tunnel stays up.
refresh_vpn_lan_filter() {
    local active
    declare -F check_vpn_killswitch >/dev/null 2>&1 || return 0
    check_vpn_killswitch || return 0
    active="$(get_vpn_active 2>/dev/null || true)"
    [[ -n "${active}" ]] || return 0
    apply_vpn_nft "${active}" 1 || true
}

# A direct address change outside the tunnel updates the bypass.
apply_vpn_nm_dhcp() {
    local iface="$1"
    load_vpn_settings
    [[ "${iface}" == "${VPN_IFACE_OVPN}" || "${iface}" == "${VPN_IFACE_WG}" ]] && return 0
    check_vpn_mode || return 0
    remember_vpn_direct_route || true
    apply_vpn_ssh || true
    apply_vpn_lan_routes || true
    refresh_vpn_lan_filter
}

# Dispatcher entry. A pause, or a foreign file, does nothing.
handle_vpn_nm_event() {
    local iface="${1:-}" action="${2:-}" profile=""
    if vpn_nm_held; then
        return 0
    fi
    read_vpn_nm_event_profile "${action}" || return 0
    case "${action}" in
        vpn-pre-up)
            apply_vpn_nm_pre_up "${profile}"
            ;;
        vpn-up)
            apply_vpn_nm_up "${profile}"
            ;;
        vpn-down)
            apply_vpn_nm_down
            ;;
        dhcp4-change | dhcp6-change)
            apply_vpn_nm_dhcp "${iface}"
            ;;
    esac
    return 0
}
