#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/nm.sh
# Updated at : 2026-11-14
# Creator    : palarchsys
# =============================================================================

vpn_nm_connection_path() {
    local name="$1" dir
    dir="${VPN_NM_DIR:-/etc/NetworkManager/system-connections}"
    printf '%s/liltress-%s.nmconnection\n' "${dir}" "${name}"
}

vpn_nm_name_of() {
    local base
    base="$(basename -- "$1")"
    base="${base#liltress-}"
    base="${base%.nmconnection}"
    printf '%s\n' "${base}"
}

vpn_nm_hold_path() {
    printf '%s/nm.hold\n' "$(get_vpn_home)"
}

vpn_nm_switch_path() {
    printf '%s/nm.switch\n' "$(get_vpn_home)"
}

vpn_nm_stamp_on() {
    local file old
    file="$1"
    mkdir -p "$(dirname -- "${file}")"
    old="$(umask)"
    umask 077
    printf '1\n' > "${file}"
    umask "${old}"
    chmod 600 "${file}"
}

vpn_nm_hold_on() {
    vpn_nm_stamp_on "$(vpn_nm_hold_path)"
}

vpn_nm_hold_off() {
    rm -f "$(vpn_nm_hold_path)"
}

vpn_nm_held() {
    [[ -f "$(vpn_nm_hold_path)" ]]
}

vpn_nm_switch_on() {
    vpn_nm_stamp_on "$(vpn_nm_switch_path)"
}

vpn_nm_switch_off() {
    rm -f "$(vpn_nm_switch_path)"
}

vpn_nm_switching() {
    [[ -f "$(vpn_nm_switch_path)" ]]
}

vpn_nm_wants_auto() {
    local name="$1" active
    if [[ "${VPN_NM_AUTOCONNECT:-}" == "0" ]]; then
        return 1
    fi
    if [[ "${VPN_NM_AUTOCONNECT:-}" == "1" ]]; then
        return 0
    fi
    check_vpn_mode || return 1
    active="$(get_vpn_active 2>/dev/null || true)"
    [[ -z "${active}" || "${active}" == "${name}" ]]
}

vpn_nm_token() {
    local raw="$1"
    raw="$(strip_vpn_text "${raw}")"
    raw="${raw#\"}"
    raw="${raw%\"}"
    raw="${raw#\'}"
    raw="${raw%\'}"
    printf '%s' "${raw}"
}

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

vpn_nm_first() {
    local rest="$1"
    rest="$(strip_vpn_text "${rest}")"
    [[ -n "${rest}" ]] || return 1
    printf '%s\n' "${rest%%[[:space:]]*}"
}

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
        done < "${path}"
    fi
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        tr -d '[:space:]' < /proc/sys/kernel/random/uuid
        return 0
    fi
    printf '%s\n' "11111111-1111-4111-8111-111111111111"
}

vpn_nm_auth_pair() {
    local file="$1" line n=0
    [[ -f "${file}" && ! -L "${file}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        n=$((n + 1))
        if (( n == 1 )); then
            printf '%s\n' "$(strip_vpn_text "${line}")"
        elif (( n == 2 )); then
            printf '%s\n' "${line}"
            return 0
        fi
    done < "${file}"
    return 1
}

vpn_nm_render_openvpn() {
    local name="$1" path="$2" dir runtime iface transport port remote v6
    local line trimmed key rest val ca="" cert="" keyf="" auth="" user="" password=""
    local rcert="" ta="" tadir="" tcrypt="" tcrypt2="" kind auto uuid tcp enc
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
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        trimmed="$(strip_vpn_text "${line}")"
        [[ -z "${trimmed}" || "${trimmed}" == \#* || "${trimmed}" == \;* ]] && continue
        key="${trimmed%%[[:space:]]*}"
        rest="$(strip_vpn_text "${trimmed#"${key}"}")"
        val="$(vpn_nm_first "${rest}" 2>/dev/null || true)"
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
            auth-user-pass)
                if [[ -n "${val}" ]]; then
                    auth="$(vpn_nm_abs "${dir}" "${val}")" || true
                else
                    auth="${dir}/auth.txt"
                fi
                ;;
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
    done < "${runtime}"
    [[ -n "${ca}" ]] || return 1
    if [[ -z "${auth}" && -f "${dir}/auth.txt" ]]; then
        auth="${dir}/auth.txt"
    fi
    if [[ -n "${auth}" && -f "${auth}" ]]; then
        user="$(vpn_nm_auth_pair "${auth}" | sed -n '1p')"
        password="$(vpn_nm_auth_pair "${auth}" | sed -n '2p')"
    fi
    if [[ -n "${cert}" && -n "${keyf}" && -n "${user}" && -n "${password}" ]]; then
        kind="password-tls"
    elif [[ -n "${user}" && -n "${password}" ]]; then
        kind="password"
    elif [[ -n "${cert}" && -n "${keyf}" ]]; then
        kind="tls"
    else
        return 1
    fi
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
    {
        printf '%s\n' '[connection]'
        printf 'id=%s\n' "${name}"
        printf 'uuid=%s\n' "${uuid}"
        printf '%s\n' 'type=vpn'
        printf 'interface-name=%s\n' "${iface}"
        printf 'autoconnect=%s\n' "${auto}"
        printf '%s\n' 'permissions='
        printf '\n'
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
        printf 'data=liltress.profile=%s\n' "${name}"
    } > "${path}"
    chmod 600 "${path}"
}

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

vpn_nm_render_wireguard() {
    local name="$1" path="$2" dir runtime iface v6 line trimmed section=""
    local key rest val field private="" pubkey="" endpoint="" keep="" psk=""
    local peers="" auto uuid addr n4=0 n6=0 v4text="" v6text=""
    dir="$(get_vpn_profile_dir "${name}")"
    runtime="${dir}/runtime"
    [[ -f "${runtime}" ]] || return 1
    load_vpn_settings
    iface="$(get_vpn_meta "${name}" iface 2>/dev/null || true)"
    [[ -n "${iface}" ]] || iface="${VPN_IFACE_WG}"
    v6="$(get_vpn_meta "${name}" has_ipv6 2>/dev/null || echo 0)"
    field="$(get_vpn_private_field)"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        trimmed="$(strip_vpn_text "${line}")"
        if [[ "${trimmed}" == \[*\] ]]; then
            if [[ "${section}" == "Peer" && -n "${pubkey}" ]]; then
                peers="${peers}$(vpn_nm_peer_block "${pubkey}" "${endpoint}" "${keep}" "${psk}")"
            fi
            section="${trimmed#[}"
            section="${section%]}"
            pubkey=""
            endpoint=""
            keep=""
            psk=""
            continue
        fi
        [[ -z "${trimmed}" || "${trimmed}" == \#* ]] && continue
        key="$(strip_vpn_text "${trimmed%%=*}")"
        rest="$(strip_vpn_text "${trimmed#*=}")"
        val="${rest}"
        if [[ "${section}" == "Interface" && "${key}" == "${field}" ]]; then
            private="${val}"
        elif [[ "${section}" == "Peer" && "${key}" == "PublicKey" ]]; then
            pubkey="${val}"
        elif [[ "${section}" == "Peer" && "${key}" == "Endpoint" ]]; then
            endpoint="${val}"
        elif [[ "${section}" == "Peer" && "${key}" == "PersistentKeepalive" ]]; then
            keep="${val}"
        elif [[ "${section}" == "Peer" && "${key}" == "PresharedKey" ]]; then
            psk="${val}"
        fi
    done < "${runtime}"
    if [[ "${section}" == "Peer" && -n "${pubkey}" ]]; then
        peers="${peers}$(vpn_nm_peer_block "${pubkey}" "${endpoint}" "${keep}" "${psk}")"
    fi
    [[ -n "${private}" && -n "${peers}" ]] || return 1
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
    if vpn_nm_wants_auto "${name}"; then
        auto="true"
    else
        auto="false"
    fi
    uuid="$(vpn_nm_uuid "${path}")"
    {
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
        printf '%s\n' '[ipv4]'
        if (( n4 > 0 )); then
            printf '%s\n' 'method=manual'
            printf '%s' "${v4text}"
        else
            printf '%s\n' 'method=disabled'
        fi
        printf '%s\n' 'ignore-auto-dns=true'
        printf '%s\n' 'never-default=false'
        printf 'route-metric=%s\n' "${VPN_ROUTE_METRIC}"
        printf '\n'
        printf '%s\n' '[ipv6]'
        printf '%s\n' 'ignore-auto-dns=true'
        if (( n6 > 0 )); then
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
        printf 'data=liltress.profile=%s\n' "${name}"
    } > "${path}"
    chmod 600 "${path}"
}

render_vpn_nm_connection() {
    local name="$1" path="$2" proto
    proto="$(get_vpn_meta "${name}" proto 2>/dev/null || true)"
    if [[ "${proto}" == "wireguard" ]]; then
        vpn_nm_render_wireguard "${name}" "${path}"
        return
    fi
    vpn_nm_render_openvpn "${name}" "${path}"
}

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

vpn_nm_set_autoconnect() {
    local name="$1" want="$2" file tmp line section="" seen=0
    if [[ "${want}" == "true" || "${want}" == "yes" || "${want}" == "1" ]]; then
        want="true"
    else
        want="false"
    fi
    file="$(vpn_nm_connection_path "${name}")"
    [[ -f "${file}" ]] || return 1
    tmp="$(mktemp "${file}.XXXXXX")"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == \[*\] ]]; then
            if [[ "${section}" == "[connection]" && "${seen}" -eq 0 ]]; then
                printf 'autoconnect=%s\n' "${want}" >> "${tmp}"
                seen=1
            fi
            section="${line}"
            printf '%s\n' "${line}" >> "${tmp}"
            continue
        fi
        if [[ "${section}" == "[connection]" && "${line}" == autoconnect=* ]]; then
            printf 'autoconnect=%s\n' "${want}" >> "${tmp}"
            seen=1
            continue
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${file}"
    if [[ "${section}" == "[connection]" && "${seen}" -eq 0 ]]; then
        printf 'autoconnect=%s\n' "${want}" >> "${tmp}"
    fi
    cat "${tmp}" > "${file}"
    rm -f "${tmp}"
    chmod 600 "${file}"
    if [[ -z "${VPN_NM_DIR:-}" ]] && command -v nmcli >/dev/null 2>&1; then
        if [[ "${want}" == "true" ]]; then
            nmcli connection modify id "${name}" connection.autoconnect yes >/dev/null 2>&1 || true
        else
            nmcli connection modify id "${name}" connection.autoconnect no >/dev/null 2>&1 || true
        fi
    fi
}

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

vpn_nm_autoconnect_all() {
    local want="$1" name
    while IFS= read -r name; do
        [[ -n "${name}" ]] || continue
        vpn_nm_set_autoconnect "${name}" "${want}" || true
    done < <(vpn_nm_each)
}

vpn_nm_prefer() {
    local name="$1" other
    while IFS= read -r other; do
        [[ -n "${other}" ]] || continue
        if [[ "${other}" == "${name}" ]]; then
            vpn_nm_set_autoconnect "${other}" true || true
        else
            vpn_nm_set_autoconnect "${other}" false || true
        fi
    done < <(vpn_nm_each)
}

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

stop_vpn_nm_all() {
    stop_vpn_nm_others ""
}

remove_vpn_nm_connection() {
    local name="$1" path nested=0
    path="$(vpn_nm_connection_path "${name}")"
    if [[ -z "${VPN_NM_DIR:-}" ]] && command -v nmcli >/dev/null 2>&1; then
        if ! vpn_nm_held; then
            vpn_nm_hold_on
            nested=1
        fi
        nmcli connection delete id "${name}" >/dev/null 2>&1 || true
        if (( nested == 1 )); then
            vpn_nm_hold_off
        fi
    fi
    rm -f "${path}"
}

vpn_nm_activated() {
    local name="$1" state
    [[ -z "${VPN_NM_DIR:-}" ]] || return 1
    command -v nmcli >/dev/null 2>&1 || return 1
    state="$(timeout 2 nmcli -g GENERAL.STATE connection show id "${name}" 2>/dev/null || true)"
    [[ "${state}" == activated* ]]
}

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

wait_vpn_nm() {
    local name="$1" deadline
    deadline=$((SECONDS + VPN_HANDSHAKE_TIMEOUT))
    while (( SECONDS <= deadline )); do
        if vpn_nm_activated "${name}"; then
            return 0
        fi
        sleep 1
    done
    return 1
}

vpn_nm_up() {
    local name="$1"
    [[ -z "${VPN_NM_DIR:-}" ]] || return 1
    command -v nmcli >/dev/null 2>&1 || return 1
    nmcli -w "${VPN_HANDSHAKE_TIMEOUT}" connection up id "${name}" >/dev/null 2>&1
}

vpn_nm_unmanage() {
    local iface="$1"
    [[ -n "${iface}" ]] || return 0
    [[ -z "${VPN_NM_DIR:-}" ]] || return 0
    command -v nmcli >/dev/null 2>&1 || return 0
    nmcli device set "${iface}" managed no >/dev/null 2>&1 || true
}

vpn_nm_set_active() {
    local name="$1" file
    if declare -F set_vpn_active >/dev/null 2>&1; then
        set_vpn_active "${name}"
        return 0
    fi
    file="$(get_vpn_home)/active"
    printf '%s\n' "${name}" > "${file}"
    chmod 600 "${file}"
}

raise_vpn_link() {
    local name="$1" rc=0
    vpn_nm_hold_on
    if ! VPN_NM_AUTOCONNECT=1 install_vpn_nm_connection "${name}"; then
        rc=1
    elif ! stop_vpn_nm_others "${name}"; then
        rc=1
    elif ! remember_vpn_direct_route; then
        rc=1
    elif ! apply_vpn_endpoint_routes "${name}"; then
        rc=1
    elif ! apply_vpn_bypass_routes; then
        rc=1
    elif ! apply_vpn_ssh; then
        rc=1
    elif ! apply_vpn_nft "${name}" 0; then
        rc=1
    elif ! vpn_nm_up "${name}"; then
        rc=1
    elif ! wait_vpn_nm "${name}"; then
        rc=1
    fi
    if (( rc == 0 )); then
        clear_vpn_tunnel_routes || true
        apply_vpn_nft "${name}" 1 || rc=1
        vpn_nm_prefer "${name}" || true
    else
        vpn_nm_set_autoconnect "${name}" false || true
        if [[ -z "${VPN_NM_DIR:-}" ]] && command -v nmcli >/dev/null 2>&1; then
            nmcli connection down id "${name}" >/dev/null 2>&1 || true
        fi
    fi
    vpn_nm_hold_off
    return "${rc}"
}

vpn_nm_profile_mark() {
    local file="${1:-}" line value
    [[ -n "${file}" && -f "${file}" && ! -L "${file}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        case "${line}" in
            data=*liltress.profile=*)
                value="${line#*liltress.profile=}"
                value="${value%%;*}"
                value="$(strip_vpn_text "${value}")"
                [[ -n "${value}" ]] || return 1
                printf '%s\n' "${value}"
                return 0
                ;;
            liltress.profile=*)
                value="$(strip_vpn_text "${line#liltress.profile=}")"
                [[ -n "${value}" ]] || return 1
                printf '%s\n' "${value}"
                return 0
                ;;
        esac
    done < "${file}"
    return 1
}

quiet_vpn_down() {
    vpn_nm_hold_on
    set_vpn_state_mode off
    load_vpn_settings
    apply_vpn_systemd || true
    clear_vpn_network
    restart_vpn_services || true
    note_vpn_log mode-off "-" ok "nm"
    vpn_nm_hold_off
}

handle_vpn_nm_event() {
    local iface="${1:-}" action="${2:-}" profile=""
    if vpn_nm_held; then
        return 0
    fi
    case "${action}" in
        vpn-pre-up|vpn-up|vpn-down|vpn-pre-down)
            profile="$(vpn_nm_profile_mark "${CONNECTION_FILENAME:-}" 2>/dev/null || true)"
            [[ -n "${profile}" ]] || return 0
            ;;
    esac
    case "${action}" in
        vpn-pre-up)
            set_vpn_state_mode on
            load_vpn_settings
            apply_vpn_systemd || true
            remember_vpn_direct_route || true
            apply_vpn_ssh || true
            apply_vpn_endpoint_routes "${profile}" || true
            apply_vpn_bypass_routes || true
            apply_vpn_nft "${profile}" 0 || true
            ;;
        vpn-up)
            set_vpn_state_mode on
            clear_vpn_tunnel_routes || true
            vpn_nm_set_active "${profile}"
            set_vpn_state_active "${profile}" || true
            record_vpn_attempt "${profile}" 1 || true
            apply_vpn_nft "${profile}" 1 || true
            restart_vpn_services || true
            note_vpn_log mode-on "${profile}" ok "nm"
            ;;
        vpn-down)
            if vpn_nm_switching || vpn_nm_any_up; then
                return 0
            fi
            quiet_vpn_down
            ;;
        dhcp4-change|dhcp6-change)
            load_vpn_settings
            [[ "${iface}" == "${VPN_IFACE_OVPN}" || "${iface}" == "${VPN_IFACE_WG}" ]] && return 0
            check_vpn_mode || return 0
            remember_vpn_direct_route || true
            apply_vpn_ssh || true
            ;;
    esac
    return 0
}
