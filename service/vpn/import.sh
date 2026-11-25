#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/import.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Install one tunnel profile from a provider file.
# Note       : An import that only stages the profile leaves the tunnel directory unchanged.
# Note       : The integrity refresh follows a successful import.
# -----------------------------------------------------------------------------


# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../core/boot/python.sh"

get_vpn_dns() {
    local host="$1"
    python3 "$(locate_python_directory)/vpn-dns.py" "${host}" 127.0.0.1
}

list_vpn_dns_rows() {
    local host="$1"
    get_vpn_dns "${host}" 2>/dev/null || true
}

emit_vpn_host_family() {
    local family="$1" address
    shift
    for address in "$@"; do
        printf '%s %s\n' "${family}" "${address}"
    done
}

read_vpn_host_answers() {
    local host="$1" row family address
    local -a v4=() v6=()
    while IFS= read -r row; do
        family="${row%% *}"
        address="${row#* }"
        if [[ "${family}" == "A" ]] && get_vpn_ipv4_parts "${address}" >/dev/null 2>&1; then
            v4+=("${address}")
        elif [[ "${family}" == "AAAA" ]] && get_vpn_v6_groups "${address}" >/dev/null 2>&1; then
            v6+=("${address}")
        fi
    done < <(list_vpn_dns_rows "${host}")
    ((${#v4[@]} + ${#v6[@]} > 0)) || return 1
    emit_vpn_host_family 4 "${v4[@]}"
    emit_vpn_host_family 6 "${v6[@]}"
}

get_vpn_host() {
    local host="$1"
    if get_vpn_ipv4_parts "${host}" >/dev/null 2>&1; then
        printf '4 %s\n' "${host}"
        return 0
    fi
    if get_vpn_v6_groups "${host}" >/dev/null 2>&1; then
        printf '6 %s\n' "${host}"
        return 0
    fi
    read_vpn_host_answers "${host}"
}

get_vpn_wg_endpoint() {
    local endpoint="$1" host port
    if [[ "${endpoint}" == \[*\]:* ]]; then
        host="${endpoint#\[}"
        host="${host%%\]*}"
        port="${endpoint##*\]:}"
    else
        host="${endpoint%:*}"
        port="${endpoint##*:}"
    fi
    [[ "${port}" =~ ^[0-9]+$ ]] || return 1
    ((port >= 1 && port <= 65535)) || return 1
    printf '%s %s\n' "${host}" "${port}"
}

check_vpn_import_name() {
    local name="$1" home dest
    check_vpn_name "${name}" || {
        if declare -F log_error >/dev/null 2>&1; then
            record_vpn_log import "${name}" fail "bad-name"
            log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.bad-name" "${name}"
        fi
        return 1
    }
    home="$(get_vpn_home)"
    mkdir -p "${home}/wireguard" "${home}/openvpn"
    chmod 700 "${home}/wireguard" "${home}/openvpn" 2>/dev/null || true
    if [[ -e "${home}/wireguard/${name}" || -e "${home}/openvpn/${name}" || -e "${home}/profiles/${name}" ]]; then
        record_vpn_log import "${name}" fail "exists"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.exists" "${name}"
    fi
}

# shellcheck disable=SC2154
fail_vpn_import_test() {
    local name="$1" proto="$2" dest="$3"
    if declare -F set_vpn_nm_hold_off >/dev/null 2>&1; then
        set_vpn_nm_hold_off
    fi
    if [[ "${VPN_NM_FAULT:-}" == "load" || "${VPN_NM_FAULT:-}" == "up" ]]; then
        record_vpn_log import "${name}" fail "networkmanager ${VPN_NM_FAULT} ${proto}"
    else
        record_vpn_log import "${name}" fail "handshake ${proto}"
    fi
    VPN_NM_FAULT=""
    if declare -F remove_vpn_nm_connection >/dev/null 2>&1; then
        remove_vpn_nm_connection "${name}" || true
    fi
    rm -rf "${dest}"
    if declare -F remove_vpn_state >/dev/null 2>&1; then
        remove_vpn_state "${name}"
    fi
    return 0
}

finish_vpn_import() {
    local work="$1" name="$2" endpoint="$3" proto="$4"
    local dest
    if [[ "${VPN_IMPORT_STAGE_ONLY:-0}" == "1" ]]; then
        VPN_STAGE_DIR="${work}"
        printf '%s\n' "${work}" >"$(get_vpn_home)/.stage-path"
        chmod 600 "$(get_vpn_home)/.stage-path"
        return 0
    fi
    dest="$(get_vpn_profile_directory "${name}" "${proto}")"
    mkdir -p "$(dirname -- "${dest}")"
    chmod 700 "$(dirname -- "${dest}")"
    chmod 700 "${work}"
    find "${work}" -type f -exec chmod 600 {} +
    mv "${work}" "${dest}"
    if declare -F set_vpn_nm_hold_on >/dev/null 2>&1; then
        set_vpn_nm_hold_on
    fi
    if declare -F run_vpn_test >/dev/null 2>&1; then
        if ! run_vpn_test "${name}"; then
            fail_vpn_import_test "${name}" "${proto}" "${dest}"
            return 1
        fi
    fi
    finish_vpn_import_open "${name}" "${endpoint}" "${proto}"
}

finish_vpn_import_open() {
    local name="$1" endpoint="$2" proto="$3"
    record_vpn_log import "${name}" ok "${proto} ${endpoint}"
    if declare -F log_success >/dev/null 2>&1; then
        log_success "${INSTALL_WATCHER:-BASH}" "vpn.import.ok" "${name}" "${endpoint}"
    fi
    refresh_rc=0
    (
        refresh_vpn_integrity
    ) || refresh_rc=$?
    if declare -F set_vpn_nm_hold_off >/dev/null 2>&1; then
        set_vpn_nm_hold_off
    fi
    if [[ "${refresh_rc}" -ne 0 ]]; then
        exit "${refresh_rc}"
    fi
}

# shellcheck disable=SC2154
take_vpn_wg_header_line() {
    local line="$1" private="$2" trimmed
    line="${line%$'\r'}"
    trimmed="$(strip_vpn_text "${line}")"
    if [[ "${trimmed}" == \[*\] ]]; then
        section="${trimmed#[}"
        section="${section%]}"
        section="$(strip_vpn_text "${section}")"
        if [[ "${section}" == "Peer" ]]; then
            peers=$((peers + 1))
        fi
        return 0
    fi
    if [[ "${trimmed}" =~ ^${private}[[:space:]]*= ]]; then
        has_private=1
    fi
    if [[ "${trimmed}" =~ ^PublicKey[[:space:]]*= ]]; then
        has_public=1
    fi
    if [[ "${section}" == "Peer" && "${trimmed}" =~ ^Endpoint[[:space:]]*= ]]; then
        endpoint_line="$(strip_vpn_text "${trimmed#*=}")"
    fi
}

read_vpn_wg_header() {
    local file="$1" private="$2" line
    local section="" peers=0 has_private=0 has_public=0 endpoint_line=""
    while IFS= read -r line || [[ -n "${line}" ]]; do
        take_vpn_wg_header_line "${line}" "${private}"
    done <"${file}"
    printf '%s\n' "${peers}" "${has_private}" "${has_public}" "${endpoint_line}"
}

require_vpn_wg_peer() {
    local work="$1" name="$2" peers="$3"
    if ((peers != 1)); then
        rm -rf "${work}"
        record_vpn_log import "${name}" fail "peer ${peers}"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.peer" "${name}" "${peers}"
        return 1
    fi
}

collect_vpn_wg_gaps() {
    local work="$1" name="$2" has_private="$3" has_public="$4" endpoint_line="$5"
    local -a lack_fields=()
    ((has_private == 1)) || lack_fields+=("$(get_vpn_private_field)")
    ((has_public == 1)) || lack_fields+=("PublicKey")
    [[ -n "${endpoint_line}" ]] || lack_fields+=("Endpoint")
    if ((${#lack_fields[@]})); then
        rm -rf "${work}"
        record_vpn_log import "${name}" fail "missing ${lack_fields[*]}"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.missing" "${name}" "${lack_fields[*]}"
        return 1
    fi
}

# shellcheck disable=SC2154
require_vpn_wg_endpoint() {
    local work="$1" name="$2" endpoint_line="$3"
    if read -r host port < <(get_vpn_wg_endpoint "${endpoint_line}"); then
        return 0
    fi
    rm -rf "${work}"
    record_vpn_log import "${name}" fail "missing Endpoint"
    log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.missing" "${name}" "Endpoint"
    return 1
}

list_vpn_host_rows() {
    local host="$1"
    get_vpn_host "${host}" || true
}

# An empty answer list still continues after the failure note.
log_vpn_import_dns() {
    local work="$1" name="$2" host="$3" count="$4"
    if ((count > 0)); then
        return 0
    fi
    rm -rf "${work}"
    record_vpn_log import "${name}" fail "dns ${host}"
    log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.dns" "${host}"
}

read_vpn_address_lists() {
    local line ep4="" ep6=""
    for line in "$@"; do
        if [[ "${line}" == 4\ * ]]; then
            ep4+="${ep4:+ }${line#4 }"
        else
            ep6+="${ep6:+ }${line#6 }"
        fi
    done
    printf '%s\n' "${ep4}"
    printf '%s\n' "${ep6}"
}

read_vpn_wg_has_ipv6() {
    local file="$1" address has_ipv6=0
    while IFS= read -r address; do
        if check_vpn_addr_v6 "${address}"; then
            has_ipv6=1
        fi
    done < <(list_vpn_wg_addresses "${file}")
    printf '%s\n' "${has_ipv6}"
}

apply_vpn_wg_import() {
    local work="$1" name="$2" brand="$3" port="$4" ep4="$5" ep6="$6"
    local pinned chosen has_ipv6
    if [[ -n "${ep4}" ]]; then
        chosen="${ep4%% *}:${port}"
        pinned="${ep4%% *}"
    else
        chosen="[${ep6%% *}]:${port}"
        pinned="${ep6%% *}"
    fi
    write_vpn_wg_runtime "${work}/source" "${work}/runtime" "${chosen}"
    chmod 600 "${work}/runtime"
    has_ipv6="$(read_vpn_wg_has_ipv6 "${work}/runtime")"
    write_vpn_meta "${work}" wireguard "${ep4}" "${ep6}" "${port}" udp \
        "${VPN_IFACE_WG:-wg-liltress}" "${has_ipv6}" 0 "${brand}"
    finish_vpn_import "${work}" "${name}" "${pinned}" wireguard
}

install_vpn_wireguard() {
    local name="$1" src="$2" brand="${3:-}" work
    local peers has_private has_public endpoint_line host port
    local ep4 ep6
    local -a rows=() header=() pair=()
    check_vpn_import_name "${name}" || return 1
    [[ -f "${src}" ]] || {
        record_vpn_log import "${name}" fail "missing $(basename -- "${src}")"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.missing" "${name}" "$(basename -- "${src}")"
        return 1
    }
    work="$(mktemp -d "$(get_vpn_home)/.import.XXXXXX")"
    chmod 700 "${work}"
    cp -a "${src}" "${work}/source"
    chmod 600 "${work}/source"
    mapfile -t header < <(read_vpn_wg_header "${work}/source" "$(get_vpn_private_field)")
    peers="${header[0]}"
    has_private="${header[1]}"
    has_public="${header[2]}"
    endpoint_line="${header[3]}"
    require_vpn_wg_peer "${work}" "${name}" "${peers}" || return 1
    collect_vpn_wg_gaps "${work}" "${name}" "${has_private}" "${has_public}" "${endpoint_line}" || return 1
    require_vpn_wg_endpoint "${work}" "${name}" "${endpoint_line}" || return 1
    mapfile -t rows < <(list_vpn_host_rows "${host}")
    log_vpn_import_dns "${work}" "${name}" "${host}" "${#rows[@]}"
    mapfile -t pair < <(read_vpn_address_lists "${rows[@]}")
    ep4="${pair[0]}"
    ep6="${pair[1]}"
    apply_vpn_wg_import "${work}" "${name}" "${brand}" "${port}" "${ep4}" "${ep6}"
}

# Each comma-separated address is printed on its own row.
list_vpn_wg_address_parts() {
    local value="$1" part
    local -a parts=()
    IFS=',' read -r -a parts <<<"${value}"
    for part in "${parts[@]}"; do
        part="$(strip_vpn_text "${part}")"
        [[ -n "${part}" ]] && printf '%s\n' "${part}"
    done
}

list_vpn_wg_addresses() {
    local file="$1" line trimmed section="" key value
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        trimmed="$(strip_vpn_text "${line}")"
        if [[ "${trimmed}" == \[*\] ]]; then
            section="${trimmed#[}"
            section="${section%]}"
            continue
        fi
        [[ "${section}" == "Interface" ]] || continue
        key="${trimmed%%=*}"
        key="$(strip_vpn_text "${key}")"
        [[ "${key}" == "Address" ]] || continue
        value="$(strip_vpn_text "${trimmed#*=}")"
        list_vpn_wg_address_parts "${value}"
    done <"${file}"
}

check_vpn_addr_v6() {
    local addr="${1%%/*}"
    [[ "${addr}" == *:* ]] || return 1
    check_vpn_v6_cidr "${addr}" "fe80::/10" && return 1
    check_vpn_v6_cidr "${addr}" "::1/128" && return 1
    return 0
}

finish_vpn_wg_section() {
    local dest="$1" endpoint="$2" section="$3" wrote_table="$4" wrote_allowed="$5" wrote_endpoint="$6"
    if [[ "${section}" == "Interface" && "${wrote_table}" -eq 0 ]]; then
        printf 'Table = off\n' >>"${dest}"
    fi
    if [[ "${section}" == "Peer" ]]; then
        if [[ "${wrote_allowed}" -ne 1 ]]; then
            printf 'AllowedIPs = 0.0.0.0/0, ::/0\n' >>"${dest}"
        fi
        if [[ "${wrote_endpoint}" -ne 1 ]]; then
            printf 'Endpoint = %s\n' "${endpoint}" >>"${dest}"
        fi
    fi
}

# shellcheck disable=SC2154
apply_vpn_wg_interface_line() {
    local line="$1" key="$2"
    if [[ "${key}" == "Table" ]]; then
        printf 'Table = off\n' >>"${dest}"
        wrote_table=1
        return 0
    fi
    if [[ "${key}" == "DNS" ]]; then
        return 0
    fi
    printf '%s\n' "${line}" >>"${dest}"
}

# shellcheck disable=SC2154
apply_vpn_wg_peer_line() {
    local line="$1" key="$2"
    if [[ "${key}" == "AllowedIPs" ]]; then
        printf 'AllowedIPs = 0.0.0.0/0, ::/0\n' >>"${dest}"
        wrote_allowed=1
        return 0
    fi
    if [[ "${key}" == "Endpoint" ]]; then
        printf 'Endpoint = %s\n' "${endpoint}" >>"${dest}"
        wrote_endpoint=1
        return 0
    fi
    printf '%s\n' "${line}" >>"${dest}"
}

# shellcheck disable=SC2154
apply_vpn_wg_runtime_line() {
    local line="$1" trimmed key
    line="${line%$'\r'}"
    trimmed="$(strip_vpn_text "${line}")"
    if [[ "${trimmed}" == \[*\] ]]; then
        finish_vpn_wg_section "${dest}" "${endpoint}" "${section}" \
            "${wrote_table}" "${wrote_allowed}" "${wrote_endpoint}"
        section="${trimmed#[}"
        section="${section%]}"
        wrote_table=0
        wrote_allowed=0
        wrote_endpoint=0
        printf '%s\n' "${trimmed}" >>"${dest}"
        return 0
    fi
    key="${trimmed%%=*}"
    key="$(strip_vpn_text "${key}")"
    case "${section}" in
        Interface) apply_vpn_wg_interface_line "${line}" "${key}" ;;
        Peer) apply_vpn_wg_peer_line "${line}" "${key}" ;;
        *) printf '%s\n' "${line}" >>"${dest}" ;;
    esac
}

write_vpn_wg_runtime() {
    local src="$1" dest="$2" endpoint="$3"
    local line section="" wrote_table=0 wrote_allowed=0 wrote_endpoint=0
    : >"${dest}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        apply_vpn_wg_runtime_line "${line}"
    done <"${src}"
    finish_vpn_wg_section "${dest}" "${endpoint}" "${section}" \
        "${wrote_table}" "${wrote_allowed}" "${wrote_endpoint}"
}

get_vpn_ovpn_token() {
    local raw="$1"
    raw="$(strip_vpn_text "${raw}")"
    raw="${raw#\"}"
    raw="${raw%\"}"
    raw="${raw#\'}"
    raw="${raw%\'}"
    printf '%s' "${raw}"
}

check_vpn_auth_file() {
    local file="$1" count=0 line
    [[ -f "${file}" ]] || return 0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        line="$(strip_vpn_text "${line}")"
        [[ -n "${line}" ]] || continue
        count=$((count + 1))
    done <"${file}"
    [[ "${count}" -ge 2 ]]
}

get_vpn_auth_line_count() {
    local file="$1" count=0 line
    [[ -f "${file}" && ! -L "${file}" ]] || {
        printf '0'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        line="$(strip_vpn_text "${line}")"
        [[ -n "${line}" ]] || continue
        count=$((count + 1))
    done <"${file}"
    printf '%s' "${count}"
}

check_vpn_auth_usable() {
    local file="$1"
    [[ -f "${file}" && ! -L "${file}" ]] || return 1
    grep -q 'REPLACE' "${file}" && return 1
    [[ "$(get_vpn_auth_line_count "${file}")" -ge 2 ]]
}

copy_vpn_material() {
    local key="$1" token="$2" extra="$3" directory="$4" work="$5"
    local path copied
    path="${token}"
    [[ "${path}" == /* ]] || path="${directory}/${path}"
    if [[ -d "${path}" ]]; then
        copied="${key}-directory"
        mkdir -p "${work}/${copied}"
        cp -a "${path}/." "${work}/${copied}/"
        chmod 700 "${work}/${copied}"
        find "${work}/${copied}" -type f -exec chmod 600 {} +
    else
        [[ -f "${path}" ]] || return 1
        copied="$(basename -- "${path}")"
        if [[ -e "${work}/${copied}" ]]; then
            copied="${key}-${copied}"
        fi
        cp -a "${path}" "${work}/${copied}"
        chmod 600 "${work}/${copied}"
    fi
    if [[ -n "${extra}" ]]; then
        printf '%s %s %s\n' "${key}" "${copied}" "${extra}" >>"${work}/runtime"
    else
        printf '%s %s\n' "${key}" "${copied}" >>"${work}/runtime"
    fi
}

# The first known login file is copied when the profile cites none.
copy_vpn_auth_candidate() {
    local directory="$1" work="$2" candidate
    for candidate in auth.txt credentials.txt login.txt pass.txt userpass.txt; do
        if [[ -f "${directory}/${candidate}" ]]; then
            cp -a "${directory}/${candidate}" "${work}/auth.txt"
            break
        fi
    done
}

copy_vpn_auth() {
    local directory="$1" work="$2" token="$3"
    local path=""
    if [[ -n "${token}" ]]; then
        path="${token}"
        [[ "${path}" == /* ]] || path="${directory}/${path}"
        [[ -f "${path}" ]] || return 1
        cp -a "${path}" "${work}/auth.txt"
    else
        copy_vpn_auth_candidate "${directory}" "${work}"
        if [[ ! -f "${work}/auth.txt" ]]; then
            return 1
        fi
    fi
    if ! check_vpn_auth_file "${work}/auth.txt"; then
        return 1
    fi
    chmod 600 "${work}/auth.txt"
    printf 'auth-user-pass auth.txt\n' >>"${work}/runtime"
}

copy_vpn_ovpn_kept() {
    printf '%s\n' "$1" >>"$2/runtime"
}

# shellcheck disable=SC2154
take_vpn_ovpn_open_tag() {
    local line="$1" trimmed="$2"
    if [[ "${trimmed}" == \<* && "${trimmed}" != \</*\> && "${trimmed}" != *\>* ]]; then
        in_tag=1
        copy_vpn_ovpn_kept "${line}" "${work}"
        return 0
    fi
    return 1
}

take_vpn_ovpn_note() {
    local line="$1" trimmed="$2"
    if [[ -z "${trimmed}" || "${trimmed}" == \#* || "${trimmed}" == \;* ]]; then
        copy_vpn_ovpn_kept "${line}" "${work}"
        return 0
    fi
    return 1
}

# shellcheck disable=SC2154
take_vpn_ovpn_remote() {
    local rest="$1" rport="" rproto=""
    remote_count=$((remote_count + 1))
    if ((remote_count > 1)); then
        extra=1
        return 0
    fi
    read -r host rport rproto <<<"${rest}"
    host="$(get_vpn_ovpn_token "${host}")"
    if [[ "${rport:-}" =~ ^(udp|tcp) ]]; then
        rproto="${rport}"
        rport=""
    fi
    if [[ -n "${rport:-}" ]]; then
        port="$(get_vpn_ovpn_token "${rport}")"
    fi
    if [[ -n "${rproto:-}" ]]; then
        proto="$(get_vpn_ovpn_token "${rproto}")"
    fi
    printf 'REMOTE %s\n' "${host}" >>"${work}/runtime"
}

# shellcheck disable=SC2154
take_vpn_ovpn_auth() {
    local rest="$1" token
    if [[ "${auth_done}" -eq 1 ]]; then
        return 0
    fi
    token="$(get_vpn_ovpn_token "${rest}")"
    if check_vpn_auth_usable "${directory}/auth.txt"; then
        token="auth.txt"
    fi
    if copy_vpn_auth "${directory}" "${work}" "${token}"; then
        auth_done=1
        return 0
    fi
    rm -rf "${work}"
    if [[ -n "${token}" && ! -f "${directory}/${token}" ]]; then
        record_vpn_log import "${name}" fail "missing $(basename -- "${token}")"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.missing" "${name}" "$(basename -- "${token}")"
    else
        record_vpn_log import "${name}" fail "auth $(get_vpn_auth_line_count "${directory}/auth.txt")"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.auth" "$(get_vpn_auth_line_count "${directory}/auth.txt")"
    fi
    return 1
}

# shellcheck disable=SC2154
take_vpn_ovpn_material() {
    local line="$1" key="$2" rest="$3" token tail
    read -r token tail <<<"${rest}"
    token="$(get_vpn_ovpn_token "${token}")"
    if [[ -z "${token}" ]]; then
        copy_vpn_ovpn_kept "${line}" "${work}"
        return 0
    fi
    tail="$(get_vpn_ovpn_token "${tail}")"
    if copy_vpn_material "${key}" "${token}" "${tail}" "${directory}" "${work}"; then
        return 0
    fi
    rm -rf "${work}"
    record_vpn_log import "${name}" fail "missing $(basename -- "${token}")"
    log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.missing" "${name}" "$(basename -- "${token}")"
    return 1
}

take_vpn_ovpn_key() {
    local line="$1" trimmed="$2" key rest
    key="${trimmed%%[[:space:]]*}"
    rest="${trimmed#"${key}"}"
    rest="$(strip_vpn_text "${rest}")"
    case "${key}" in
        proto)
            proto="$(get_vpn_ovpn_token "${rest}")"
            copy_vpn_ovpn_kept "${line}" "${work}"
            ;;
        port)
            port="$(get_vpn_ovpn_token "${rest}")"
            copy_vpn_ovpn_kept "${line}" "${work}"
            ;;
        remote) take_vpn_ovpn_remote "${rest}" ;;
        auth-user-pass) take_vpn_ovpn_auth "${rest}" ;;
        ca | cert | key | tls-crypt | tls-auth | tls-crypt-v2 | dh | pkcs12 | secret | extra-certs | crl-verify | askpass)
            take_vpn_ovpn_material "${line}" "${key}" "${rest}"
            ;;
        dev | dev-type | up | down | route-up | route-pre-down | learn-address | comp-lzo | compress | redirect-gateway | redirect-private | dhcp-option) ;;
        *) copy_vpn_ovpn_kept "${line}" "${work}" ;;
    esac
}

# shellcheck disable=SC2154
apply_vpn_ovpn_line() {
    local line="$1" trimmed
    line="${line%$'\r'}"
    trimmed="$(strip_vpn_text "${line}")"
    if [[ "${in_tag}" -eq 1 ]]; then
        copy_vpn_ovpn_kept "${line}" "${work}"
        if [[ "${trimmed}" == \</*\> ]]; then
            in_tag=0
        fi
        return 0
    fi
    if take_vpn_ovpn_open_tag "${line}" "${trimmed}"; then
        return 0
    fi
    if take_vpn_ovpn_note "${line}" "${trimmed}"; then
        return 0
    fi
    take_vpn_ovpn_key "${line}" "${trimmed}"
}

# shellcheck disable=SC2154
require_vpn_ovpn_remote() {
    if [[ -n "${host}" ]]; then
        return 0
    fi
    rm -rf "${work}"
    record_vpn_log import "${name}" fail "missing remote"
    log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.missing" "${name}" "remote"
    return 1
}

# shellcheck disable=SC2154
require_vpn_ovpn_proto() {
    case "${proto}" in
        udp | udp4 | udp6) proto="udp" ;;
        tcp | tcp4 | tcp6 | tcp-client | tcp-server) proto="tcp" ;;
        *)
            rm -rf "${work}"
            record_vpn_log import "${name}" fail "missing proto"
            log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.missing" "${name}" "proto"
            return 1
            ;;
    esac
}

# shellcheck disable=SC2154
require_vpn_ovpn_port() {
    if [[ "${port}" =~ ^[0-9]+$ ]]; then
        return 0
    fi
    rm -rf "${work}"
    record_vpn_log import "${name}" fail "missing port"
    log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.missing" "${name}" "port"
    return 1
}

require_vpn_ovpn_shape() {
    require_vpn_ovpn_remote || return 1
    require_vpn_ovpn_proto || return 1
    require_vpn_ovpn_port || return 1
}

get_vpn_import_pin() {
    local ep4="$1" ep6="$2"
    if [[ -n "${ep4}" ]]; then
        printf '%s\n' "${ep4%% *}"
        return 0
    fi
    printf '%s\n' "${ep6%% *}"
}

finish_vpn_ovpn_import() {
    local work="$1" name="$2" brand="$3" ep4="$4" ep6="$5" port="$6" proto="$7" pinned="$8" extra="$9"
    local enc=0
    sed -i "s|^REMOTE .*|remote ${pinned} ${port} ${proto}|" "${work}/runtime"
    printf 'dev %s\ndev-type tun\n' "${VPN_IFACE_OVPN}" >>"${work}/runtime"
    chmod 600 "${work}/runtime"
    if grep -q 'ENCRYPTED' "${work}/source" "${work}/runtime" "${work}"/* 2>/dev/null; then
        enc=1
    fi
    write_vpn_meta "${work}" openvpn "${ep4}" "${ep6}" "${port}" "${proto}" \
        "${VPN_IFACE_OVPN}" 0 "${enc}" "${brand}"
    if ((extra == 1)) && declare -F log_info >/dev/null 2>&1; then
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.import.remote" "${pinned}"
    fi
    finish_vpn_import "${work}" "${name}" "${pinned}" openvpn
}

install_vpn_openvpn() {
    local name="$1" src="$2" brand="${3:-}" work directory line
    local in_tag=0 proto="udp" port="1194" remote_count=0 host="" extra=0 auth_done=0
    local ep4="" ep6="" pinned=""
    local -a rows=() pair=()
    check_vpn_import_name "${name}" || return 1
    [[ -f "${src}" ]] || {
        record_vpn_log import "${name}" fail "missing $(basename -- "${src}")"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.missing" "${name}" "$(basename -- "${src}")"
        return 1
    }
    load_vpn_settings
    directory="$(cd -- "$(dirname -- "${src}")" && pwd)"
    work="$(mktemp -d "$(get_vpn_home)/.import.XXXXXX")"
    chmod 700 "${work}"
    cp -a "${src}" "${work}/source"
    chmod 600 "${work}/source"
    : >"${work}/runtime"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        apply_vpn_ovpn_line "${line}" || return 1
    done <"${work}/source"
    require_vpn_ovpn_shape || return 1
    mapfile -t rows < <(list_vpn_host_rows "${host}")
    log_vpn_import_dns "${work}" "${name}" "${host}" "${#rows[@]}"
    mapfile -t pair < <(read_vpn_address_lists "${rows[@]}")
    ep4="${pair[0]}"
    ep6="${pair[1]}"
    pinned="$(get_vpn_import_pin "${ep4}" "${ep6}")"
    finish_vpn_ovpn_import "${work}" "${name}" "${brand}" "${ep4}" "${ep6}" \
        "${port}" "${proto}" "${pinned}" "${extra}"
}

warn_vpn_refresh_name() {
    local name="$1"
    if ! check_vpn_name "${name}"; then
        record_vpn_log refresh "${name}" fail "bad-name"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.bad-name" "${name}"
    fi
    if [[ ! -f "$(get_vpn_profile_directory "${name}")/meta" ]]; then
        record_vpn_log refresh "${name}" fail "missing"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.rm.missing" "${name}"
    fi
}

# shellcheck disable=SC2154
read_vpn_refresh_wg_host() {
    local name="$1" directory="$2"
    host="$(awk -F= '/^[[:space:]]*Endpoint[[:space:]]*=/{print $2; exit}' "${directory}/source")"
    host="$(strip_vpn_text "${host}")"
    read -r host port < <(get_vpn_wg_endpoint "${host}") || {
        record_vpn_log refresh "${name}" fail "endpoint"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.refresh.fail" "${name}"
    }
}

pass_vpn_refresh_literal() {
    local name="$1" host="$2"
    if get_vpn_ipv4_parts "${host}" >/dev/null 2>&1 || get_vpn_v6_groups "${host}" >/dev/null 2>&1; then
        record_vpn_log refresh "${name}" ok "${host}"
        log_success "${INSTALL_WATCHER:-BASH}" "vpn.refresh.ok" "${name}" "${host}"
        return 0
    fi
    return 1
}

log_vpn_refresh_dns() {
    local name="$1" count="$2"
    if ((count > 0)); then
        return 0
    fi
    record_vpn_log refresh "${name}" fail "dns"
    log_error "${INSTALL_WATCHER:-BASH}" "vpn.refresh.fail" "${name}"
}

apply_vpn_refresh_target() {
    local name="$1" proto="$2" directory="$3" runtime="$4" port="$5" ep4="$6" ep6="$7"
    local pinned chosen
    if [[ -n "${ep4}" ]]; then
        pinned="${ep4%% *}"
        chosen="${pinned}:${port}"
    else
        pinned="${ep6%% *}"
        chosen="[${pinned}]:${port}"
    fi
    write_vpn_meta "${directory}" "${proto}" "${ep4}" "${ep6}" "${port}" \
        "$(get_vpn_meta "${name}" transport)" \
        "$(get_vpn_meta "${name}" iface)" \
        "$(get_vpn_meta "${name}" has_ipv6)" \
        "$(get_vpn_meta "${name}" encrypted)" \
        "$(get_vpn_meta "${name}" brand 2>/dev/null || true)"
    if [[ "${proto}" == "wireguard" ]]; then
        sed -i "s|^[[:space:]]*Endpoint[[:space:]]*=.*|Endpoint = ${chosen}|" "${runtime}"
    else
        sed -i "s|^[[:space:]]*remote[[:space:]].*|remote ${pinned} ${port} $(get_vpn_meta "${name}" transport)|" "${runtime}"
    fi
    chmod 600 "${runtime}" "${directory}/meta"
    if [[ "$(get_vpn_active 2>/dev/null || true)" == "${name}" ]]; then
        apply_vpn_endpoint_routes "${name}"
        apply_vpn_nft "${name}" 1
        log_success "${INSTALL_WATCHER:-BASH}" "vpn.refresh.active" "${name}"
    fi
    record_vpn_log refresh "${name}" ok "${pinned}"
    log_success "${INSTALL_WATCHER:-BASH}" "vpn.refresh.ok" "${name}" "${pinned}"
    refresh_vpn_integrity
}

refresh_vpn_endpoint() {
    local name="$1" proto host port ep4="" ep6=""
    local directory runtime
    local -a rows=() pair=()
    warn_vpn_refresh_name "${name}"
    proto="$(get_vpn_meta "${name}" proto)"
    port="$(get_vpn_meta "${name}" port)"
    directory="$(get_vpn_profile_directory "${name}")"
    runtime="${directory}/runtime"
    if [[ "${proto}" == "wireguard" ]]; then
        read_vpn_refresh_wg_host "${name}" "${directory}"
    else
        host="$(awk '/^[[:space:]]*remote[[:space:]]/{print $2; exit}' "${directory}/source")"
        host="$(get_vpn_ovpn_token "${host}")"
    fi
    pass_vpn_refresh_literal "${name}" "${host}" && return 0
    mapfile -t rows < <(list_vpn_host_rows "${host}")
    log_vpn_refresh_dns "${name}" "${#rows[@]}"
    mapfile -t pair < <(read_vpn_address_lists "${rows[@]}")
    ep4="${pair[0]}"
    ep6="${pair[1]}"
    apply_vpn_refresh_target "${name}" "${proto}" "${directory}" "${runtime}" "${port}" "${ep4}" "${ep6}"
}

# Cited file names are printed. Inline tags and blank rows are skipped.
emit_vpn_brand_cited() {
    local ovpn="$1" line trimmed key rest token
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        trimmed="$(strip_vpn_text "${line}")"
        [[ -z "${trimmed}" || "${trimmed}" == \#* || "${trimmed}" == \;* ]] && continue
        key="${trimmed%%[[:space:]]*}"
        rest="${trimmed#"${key}"}"
        rest="$(strip_vpn_text "${rest}")"
        case "${key}" in
            ca | cert | key | tls-crypt | tls-auth | tls-crypt-v2 | dh | pkcs12 | secret | extra-certs | crl-verify | askpass)
                token="$(get_vpn_ovpn_token "${rest}")"
                token="${token%%[[:space:]]*}"
                [[ -z "${token}" || "${token}" == \<* ]] && continue
                basename -- "${token}"
                ;;
        esac
    done <"${ovpn}"
}

check_vpn_brand_cited() {
    local ovpn="$1"
    [[ -f "${ovpn}" ]] || return 0
    emit_vpn_brand_cited "${ovpn}"
}

# shellcheck disable=SC2154
collect_vpn_brand_expected() {
    local directory="$1" name
    shift
    for name in "$@"; do
        expect+="${expect:+ }${name}"
        if [[ -L "${directory}/${name}" || (-e "${directory}/${name}" && ! -f "${directory}/${name}") ]]; then
            VPN_IMPORT_FAULT=$'notfile\t'"${name}"
            return 2
        fi
        if [[ -f "${directory}/${name}" ]]; then
            allow["${name}"]=1
        else
            missing+=("${name}")
        fi
    done
    return 0
}

# shellcheck disable=SC2154
read_vpn_brand_ovpn() {
    local directory="$1" ovpn="" cited
    if [[ -f "${directory}/config.ovpn" ]]; then
        ovpn="${directory}/config.ovpn"
    elif [[ -f "${directory}/openvpn.ovpn" ]]; then
        ovpn="${directory}/openvpn.ovpn"
    fi
    if [[ -z "${ovpn}" ]]; then
        return 0
    fi
    while IFS= read -r cited; do
        if [[ -n "${cited}" ]]; then
            allow["${cited}"]=1
        fi
    done < <(check_vpn_brand_cited "${ovpn}")
}

# shellcheck disable=SC2154
check_vpn_brand_entry() {
    local name="$1" base="$2"
    if [[ -L "${name}" || ! -f "${name}" ]]; then
        VPN_IMPORT_FAULT=$'notfile\t'"${base}"
        return 2
    fi
    found+="${found:+ }${base}"
    if [[ -z "${allow[${base}]+x}" && ${#missing[@]} -eq 0 ]]; then
        VPN_IMPORT_FAULT=$'extra\t'"${base}"$'\t'"${expect}"
        return 2
    fi
    return 0
}

# shellcheck disable=SC2154
finish_vpn_brand_names() {
    local miss
    if ((${#missing[@]})); then
        miss="${missing[*]}"
        VPN_IMPORT_FAULT=$'lack\t'"${miss}"$'\t'"${expect}"$'\t'"${found}"
        return 2
    fi
    return 0
}

get_vpn_brand_names() {
    local directory="$1" name base expect="" found=""
    shift
    local -a missing=()
    local -A allow=()
    VPN_IMPORT_FAULT=""
    collect_vpn_brand_expected "${directory}" "$@" || return 2
    read_vpn_brand_ovpn "${directory}"
    for name in "${directory}"/*; do
        [[ -e "${name}" || -L "${name}" ]] || continue
        base="$(basename -- "${name}")"
        check_vpn_brand_entry "${name}" "${base}" || return 2
    done
    finish_vpn_brand_names
}

check_vpn_brand_plain() {
    local directory="$1" file base
    for file in "${directory}"/*; do
        [[ -e "${file}" || -L "${file}" ]] || continue
        [[ -f "${file}" && ! -L "${file}" ]] || continue
        if grep -q 'REPLACE' "${file}"; then
            base="$(basename -- "${file}")"
            VPN_IMPORT_FAULT=$'replace\t'"${base}"
            return 3
        fi
    done
    return 0
}

check_vpn_brand_openvpn() {
    local directory="$1" count
    shift
    get_vpn_brand_names "${directory}" "$@" || return 2
    check_vpn_brand_plain "${directory}" || return 3
    count="$(get_vpn_auth_line_count "${directory}/auth.txt")"
    if [[ "${count}" -lt 2 ]]; then
        VPN_IMPORT_FAULT=$'auth\t'"${count}"
        return 4
    fi
    return 0
}

check_vpn_brand_wireguard() {
    local directory="$1"
    get_vpn_brand_names "${directory}" config.conf || return 2
    check_vpn_brand_plain "${directory}" || return 3
}

log_vpn_import_fault() {
    local name="$1" kind rest a b c
    kind="${VPN_IMPORT_FAULT%%$'\t'*}"
    rest="${VPN_IMPORT_FAULT#*$'\t'}"
    [[ "${rest}" == "${VPN_IMPORT_FAULT}" ]] && rest=""
    record_vpn_log import "${name}" fail "${kind} ${rest}"
    case "${kind}" in
        absent) log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.absent" "${rest}" ;;
        zipfile) log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.zipfile" "${rest}" ;;
        zipdir) log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.zipdir" "${rest}" ;;
        zipdeep) log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.zipdeep" "${rest}" ;;
        zipsize) log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.zipsize" "${rest}" ;;
        zipcount) log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.zipcount" "${rest}" ;;
        notfile) log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.notfile" "${rest}" ;;
        lack)
            IFS=$'\t' read -r a b c <<<"${rest}"
            log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.lack" "${a}" "${b}" "${c}"
            ;;
        extra)
            IFS=$'\t' read -r a b <<<"${rest}"
            log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.extra" "${a}" "${b}"
            ;;
        replace) log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.replace" "${rest}" ;;
        auth) log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.auth" "${rest}" ;;
        *) log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.shape" "${name}" ;;
    esac
    return 1
}

copy_vpn_named_file() {
    local src="$1" dest="$2" name="$3" base size
    base="$(basename -- "${src}")"
    size="$(stat -c '%s' -- "${src}" 2>/dev/null || printf '0')"
    if ((size > 1048576)); then
        VPN_IMPORT_FAULT=$'zipsize\t'"${base}"
        return 1
    fi
    cp -a -- "${src}" "${dest}/${name}" || return 1
    chmod 600 "${dest}/${name}"
}

take_vpn_import_file() {
    local src="$1" dest="$2" base
    base="$(basename -- "${src}")"
    [[ -e "${dest}/${base}" ]] && return 2
    copy_vpn_named_file "${src}" "${dest}" "${base}"
}

# A link or another special file cannot be a profile entry.
fail_vpn_directory_entry() {
    local name="$1" base="$2"
    if [[ -L "${name}" || (! -f "${name}" && ! -d "${name}") ]]; then
        VPN_IMPORT_FAULT=$'notfile\t'"${base}"
        return 1
    fi
    return 0
}

# shellcheck disable=SC2154
scan_vpn_directory_child() {
    local path="$1" name base
    for name in "${path}"/*; do
        [[ -e "${name}" || -L "${name}" ]] || continue
        base="$(basename -- "${name}")"
        fail_vpn_directory_entry "${name}" "${base}" || return 1
        if [[ -d "${name}" ]]; then
            subs=$((subs + 1))
            sub="${name}"
            continue
        fi
        roots+=("${name}")
    done
    return 0
}

# shellcheck disable=SC2154
fail_vpn_directory_many() {
    if ((subs > 1)); then
        VPN_IMPORT_FAULT=$'zipdir\t'"$(basename -- "${sub}")"
        return 1
    fi
    return 0
}

# shellcheck disable=SC2154
check_vpn_directory_auth_only() {
    local name base folder
    folder="$(basename -- "${sub}")"
    for name in "${roots[@]+"${roots[@]}"}"; do
        base="$(basename -- "${name}")"
        if [[ "${base}" != "auth.txt" ]]; then
            VPN_IMPORT_FAULT=$'zipdir\t'"${folder}"
            return 1
        fi
    done
    return 0
}

# shellcheck disable=SC2154
read_vpn_directory_nested() {
    local name base count=0
    for name in "${sub}"/*; do
        [[ -e "${name}" || -L "${name}" ]] || continue
        base="$(basename -- "${name}")"
        if [[ -d "${name}" ]]; then
            VPN_IMPORT_FAULT=$'zipdeep\t'"$(basename -- "${sub}")/${base}"
            return 1
        fi
        if [[ -L "${name}" || ! -f "${name}" ]]; then
            VPN_IMPORT_FAULT=$'notfile\t'"${base}"
            return 1
        fi
        count=$((count + 1))
    done
    nested_count=$((count + ${#roots[@]}))
    return 0
}

check_vpn_directory_nested_count() {
    local count="$1" folder="$2"
    if ((count == 0)); then
        VPN_IMPORT_FAULT=$'zipdir\t'"${folder}"
        return 1
    fi
    if ((count > 12)); then
        VPN_IMPORT_FAULT=$'zipcount\t'"${count}"
        return 1
    fi
    return 0
}

# shellcheck disable=SC2154
copy_vpn_directory_roots() {
    local dest="$1" folder="$2" name rc=0
    for name in "${roots[@]+"${roots[@]}"}"; do
        take_vpn_import_file "${name}" "${dest}" || rc=$?
        if ((rc != 0)); then
            [[ -n "${VPN_IMPORT_FAULT}" ]] || VPN_IMPORT_FAULT=$'zipdir\t'"${folder}"
            return 1
        fi
    done
    return 0
}

# shellcheck disable=SC2154
copy_vpn_directory_files() {
    local dest="$1" folder="$2" name rc=0
    for name in "${sub}"/*; do
        [[ -f "${name}" && ! -L "${name}" ]] || continue
        take_vpn_import_file "${name}" "${dest}" || rc=$?
        if ((rc != 0)); then
            [[ -n "${VPN_IMPORT_FAULT}" ]] || VPN_IMPORT_FAULT=$'zipdir\t'"${folder}"
            return 1
        fi
    done
    return 0
}

# shellcheck disable=SC2154
copy_vpn_directory_nested() {
    local dest="$1" nested_count=0 folder
    check_vpn_directory_auth_only || return 1
    read_vpn_directory_nested || return 1
    folder="$(basename -- "${sub}")"
    check_vpn_directory_nested_count "${nested_count}" "${folder}" || return 1
    copy_vpn_directory_roots "${dest}" "${folder}" || return 1
    copy_vpn_directory_files "${dest}" "${folder}" || return 1
}

# shellcheck disable=SC2154
copy_vpn_directory_flat() {
    local dest="$1" name
    if ((${#roots[@]} == 0)); then
        VPN_IMPORT_FAULT=$'zipcount\t0'
        return 1
    fi
    if ((${#roots[@]} > 12)); then
        VPN_IMPORT_FAULT=$'zipcount\t'"${#roots[@]}"
        return 1
    fi
    for name in "${roots[@]}"; do
        take_vpn_import_file "${name}" "${dest}" || return 1
    done
    return 0
}

read_vpn_directory() {
    local path="$1" dest="$2" sub="" subs=0
    local -a roots=()
    scan_vpn_directory_child "${path}" || return 1
    fail_vpn_directory_many || return 1
    if ((subs == 1)); then
        copy_vpn_directory_nested "${dest}" || return 1
        return 0
    fi
    copy_vpn_directory_flat "${dest}"
}

check_vpn_zip_file() {
    local src="$1" base sig
    base="$(basename -- "${src}")"
    case "${base}" in
        *.zip | *.ZIP) return 0 ;;
    esac
    sig="$(od -An -tx1 -N 4 -- "${src}" 2>/dev/null | tr -d ' \n')"
    [[ "${sig}" == 504b0304 || "${sig}" == 504b0506 || "${sig}" == 504b0708 ]]
}

copy_vpn_one_file() {
    local src="$1" dest="$2" base
    base="$(basename -- "${src}")"
    if [[ -L "${src}" || ! -f "${src}" ]]; then
        VPN_IMPORT_FAULT=$'notfile\t'"${base}"
        return 1
    fi
    if check_vpn_zip_file "${src}"; then
        VPN_IMPORT_FAULT=$'zipfile\t'"${base}"
        return 1
    fi
    copy_vpn_named_file "${src}" "${dest}" "config.conf"
}

read_vpn_bundle() {
    local path="$1" dest="$2" base
    VPN_IMPORT_FAULT=""
    if [[ -d "${path}" ]]; then
        read_vpn_directory "${path}" "${dest}"
        return
    fi
    if [[ ! -e "${path}" ]]; then
        VPN_IMPORT_FAULT=$'absent\t'"${path}"
        return 1
    fi
    base="$(basename -- "${path}")"
    if [[ -L "${path}" || ! -f "${path}" ]]; then
        VPN_IMPORT_FAULT=$'notfile\t'"${base}"
        return 1
    fi
    copy_vpn_one_file "${path}" "${dest}"
}

# shellcheck disable=SC2154
ensure_vpn_bundle_directory() {
    local name="$1" path="$2"
    if [[ ! -e "${path}" ]]; then
        record_vpn_log import "${name}" fail "absent ${path}"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.absent" "${path}"
        return 1
    fi
    dest="$(mktemp -d "$(get_vpn_home)/.bundle.XXXXXX")"
    chmod 700 "${dest}"
    if read_vpn_bundle "${path}" "${dest}"; then
        return 0
    fi
    rm -rf "${dest}"
    log_vpn_import_fault "${name}"
    return 1
}

# shellcheck disable=SC2154
require_vpn_bundle_brand() {
    local name="$1" brand="$2" proto="$3" rc=0
    if ! declare -F "check_vpn_brand_${brand}" >/dev/null 2>&1; then
        rm -rf "${dest}"
        record_vpn_log import "${name}" fail "brand ${brand} ${proto}"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.brand" "${brand}" "${proto}"
        return 1
    fi
    "check_vpn_brand_${brand}" "${proto}" "${dest}" || rc=$?
    if ((rc == 0)); then
        return 0
    fi
    rm -rf "${dest}"
    if ((rc == 1)); then
        record_vpn_log import "${name}" fail "brand ${brand} ${proto}"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.brand" "${brand}" "${proto}"
        return 1
    fi
    log_vpn_import_fault "${name}"
    return 1
}

# shellcheck disable=SC2154
set_vpn_bundle_src() {
    local proto="$1" brand="$2" name="$3"
    case "${proto}" in
        wireguard) src="${dest}/config.conf" ;;
        openvpn)
            if [[ -f "${dest}/openvpn.ovpn" ]]; then
                src="${dest}/openvpn.ovpn"
            else
                src="${dest}/config.ovpn"
            fi
            ;;
        *)
            rm -rf "${dest}"
            record_vpn_log import "${name}" fail "brand ${brand} ${proto}"
            log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.brand" "${brand}" "${proto}"
            return 1
            ;;
    esac
}

run_vpn_bundle_install() {
    local proto="$1" name="$2" src="$3" brand="$4" dest="$5"
    local rc=0 stage_file
    stage_file="$(get_vpn_home)/.stage-path"
    rm -f "${stage_file}"
    (
        case "${proto}" in
            wireguard) install_vpn_wireguard "${name}" "${src}" "${brand}" ;;
            openvpn) install_vpn_openvpn "${name}" "${src}" "${brand}" ;;
        esac
    ) || rc=$?
    if [[ -f "${stage_file}" ]]; then
        VPN_STAGE_DIR="$(tr -d '[:space:]' <"${stage_file}")"
        rm -f "${stage_file}"
    fi
    rm -rf "${dest}"
    return "${rc}"
}

install_vpn_bundle() {
    local proto="$1" brand="$2" name="$3" path="$4"
    local dest src
    check_vpn_import_name "${name}" || return 1
    ensure_vpn_bundle_directory "${name}" "${path}" || return 1
    require_vpn_bundle_brand "${name}" "${brand}" "${proto}" || return 1
    set_vpn_bundle_src "${proto}" "${brand}" "${name}" || return 1
    run_vpn_bundle_install "${proto}" "${name}" "${src}" "${brand}" "${dest}"
}

# shellcheck disable=SC1091
for VPN_BRAND_FILE in "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/brands/"*.sh; do
    [[ -f "${VPN_BRAND_FILE}" ]] || continue
    # shellcheck disable=SC1090
    source "${VPN_BRAND_FILE}"
done
unset VPN_BRAND_FILE
