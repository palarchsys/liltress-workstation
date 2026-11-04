#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/import.sh
# Updated at : 2026-11-04
# Creator    : palarchsys
# =============================================================================

get_vpn_dns() {
    local host="$1"
    python3 - "${host}" 127.0.0.1 << 'PY'
import socket
import sys

name = sys.argv[1]
server = sys.argv[2]

def build(qname, qtype):
    header = (0x4C54).to_bytes(2, "big") + b"\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00"
    labels = b""
    for part in qname.rstrip(".").split("."):
        raw = part.encode("idna")
        if not raw or len(raw) > 63:
            raise SystemExit(2)
        labels += bytes([len(raw)]) + raw
    return header + labels + b"\x00" + qtype.to_bytes(2, "big") + (1).to_bytes(2, "big")

def skip_name(data, index):
    hops = 0
    while hops < 30:
        if index >= len(data):
            raise ValueError("short")
        length = data[index]
        if length == 0:
            return index + 1
        if length & 0xC0 == 0xC0:
            return index + 2
        if length & 0xC0:
            raise ValueError("label")
        index += 1 + length
        hops += 1
    raise ValueError("loop")

def query(qtype):
    packet = build(name, qtype)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(3)
    try:
        sock.sendto(packet, (server, 53))
        data, _addr = sock.recvfrom(4096)
    finally:
        sock.close()
    if len(data) < 12 or data[0:2] != b"\x4c\x54":
        return []
    questions = int.from_bytes(data[4:6], "big")
    answers = int.from_bytes(data[6:8], "big")
    index = 12
    for _ in range(questions):
        index = skip_name(data, index)
        index += 4
    found = []
    for _ in range(answers):
        index = skip_name(data, index)
        kind = int.from_bytes(data[index:index + 2], "big")
        index += 8
        length = int.from_bytes(data[index:index + 2], "big")
        index += 2
        body = data[index:index + length]
        index += length
        if kind == 1 and length == 4:
            found.append("A " + socket.inet_ntoa(body))
        elif kind == 28 and length == 16:
            found.append("AAAA " + socket.inet_ntop(socket.AF_INET6, body))
    return found

rows = []
for kind in (1, 28):
    try:
        rows.extend(query(kind))
    except Exception:
        continue
if not rows:
    raise SystemExit(1)
print("\n".join(rows))
PY
}

get_vpn_host() {
    local host="$1" row family address
    local -a v4=() v6=()
    if get_vpn_ipv4_parts "${host}" >/dev/null 2>&1; then
        printf '4 %s\n' "${host}"
        return 0
    fi
    if get_vpn_v6_groups "${host}" >/dev/null 2>&1; then
        printf '6 %s\n' "${host}"
        return 0
    fi
    while IFS= read -r row; do
        family="${row%% *}"
        address="${row#* }"
        if [[ "${family}" == "A" ]] && get_vpn_ipv4_parts "${address}" >/dev/null 2>&1; then
            v4+=("${address}")
        elif [[ "${family}" == "AAAA" ]] && get_vpn_v6_groups "${address}" >/dev/null 2>&1; then
            v6+=("${address}")
        fi
    done < <(get_vpn_dns "${host}" 2>/dev/null || true)
    (( ${#v4[@]} + ${#v6[@]} > 0 )) || return 1
    for address in "${v4[@]}"; do
        printf '4 %s\n' "${address}"
    done
    for address in "${v6[@]}"; do
        printf '6 %s\n' "${address}"
    done
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
    (( port >= 1 && port <= 65535 )) || return 1
    printf '%s %s\n' "${host}" "${port}"
}

check_vpn_import_name() {
    local name="$1" home dest
    check_vpn_name "${name}" || {
        if declare -F log_error >/dev/null 2>&1; then
            log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.bad-name" "${name}"
        fi
        return 1
    }
    home="$(get_vpn_home)"
    mkdir -p "${home}/wireguard" "${home}/openvpn"
    chmod 700 "${home}/wireguard" "${home}/openvpn" 2>/dev/null || true
    if [[ -e "${home}/wireguard/${name}" || -e "${home}/openvpn/${name}" || -e "${home}/profiles/${name}" ]]; then
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.exists" "${name}"
    fi
}

finish_vpn_import() {
    local work="$1" name="$2" endpoint="$3" proto="$4"
    local dest
    dest="$(get_vpn_profile_dir "${name}" "${proto}")"
    mkdir -p "$(dirname -- "${dest}")"
    chmod 700 "$(dirname -- "${dest}")"
    chmod 700 "${work}"
    find "${work}" -type f -exec chmod 600 {} +
    mv "${work}" "${dest}"
    if declare -F log_success >/dev/null 2>&1; then
        log_success "${INSTALL_WATCHER:-BASH}" "vpn.import.ok" "${name}" "${endpoint}"
    fi
}

install_vpn_wireguard() {
    local name="$1" src="$2" work private line trimmed section=""
    local peers=0 has_private=0 has_public=0 endpoint_line="" host port
    local ep4="" ep6="" pinned="" chosen="" address v6=0
    local -a rows=()
    check_vpn_import_name "${name}" || return 1
    [[ -f "${src}" ]] || log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.missing" "${name}"
    private="$(get_vpn_private_field)"
    work="$(mktemp -d "$(get_vpn_home)/.import.XXXXXX")"
    chmod 700 "${work}"
    cp -a "${src}" "${work}/source"
    chmod 600 "${work}/source"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        trimmed="$(strip_vpn_text "${line}")"
        if [[ "${trimmed}" == \[*\] ]]; then
            section="${trimmed#[}"
            section="${section%]}"
            section="$(strip_vpn_text "${section}")"
            [[ "${section}" == "Peer" ]] && peers=$((peers + 1))
            continue
        fi
        [[ "${trimmed}" =~ ^${private}[[:space:]]*= ]] && has_private=1
        [[ "${trimmed}" =~ ^PublicKey[[:space:]]*= ]] && has_public=1
        if [[ "${section}" == "Peer" && "${trimmed}" =~ ^Endpoint[[:space:]]*= ]]; then
            endpoint_line="$(strip_vpn_text "${trimmed#*=}")"
        fi
    done < "${work}/source"
    if (( peers != 1 || has_private != 1 || has_public != 1 || -z "${endpoint_line}" )); then
        rm -rf "${work}"
        if (( peers != 1 )); then
            log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.peer" "${name}"
        fi
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.missing" "${name}"
    fi
    read -r host port < <(get_vpn_wg_endpoint "${endpoint_line}") || {
        rm -rf "${work}"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.missing" "${name}"
    }
    mapfile -t rows < <(get_vpn_host "${host}" || true)
    if (( ${#rows[@]} == 0 )); then
        rm -rf "${work}"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.dns" "${host}"
    fi
    for line in "${rows[@]}"; do
        if [[ "${line}" == 4\ * ]]; then
            ep4+="${ep4:+ }${line#4 }"
        else
            ep6+="${ep6:+ }${line#6 }"
        fi
    done
    if [[ -n "${ep4}" ]]; then
        chosen="${ep4%% *}:${port}"
        pinned="${ep4%% *}"
    else
        chosen="[${ep6%% *}]:${port}"
        pinned="${ep6%% *}"
    fi
    write_vpn_wg_runtime "${work}/source" "${work}/runtime" "${chosen}"
    chmod 600 "${work}/runtime"
    while IFS= read -r address; do
        if check_vpn_addr_v6 "${address}"; then
            v6=1
        fi
    done < <(list_vpn_wg_addresses "${work}/runtime")
    write_vpn_meta "${work}" wireguard "${ep4}" "${ep6}" "${port}" udp "${W_VPN_IFACE_WG:-wg-liltress}" "${v6}" 0
    finish_vpn_import "${work}" "${name}" "${pinned}" wireguard
}

list_vpn_wg_addresses() {
    local file="$1" line trimmed section="" key value part
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
        IFS=',' read -r -a parts <<< "${value}"
        for part in "${parts[@]}"; do
            part="$(strip_vpn_text "${part}")"
            [[ -n "${part}" ]] && printf '%s\n' "${part}"
        done
    done < "${file}"
}

check_vpn_addr_v6() {
    local addr="${1%%/*}"
    [[ "${addr}" == *:* ]] || return 1
    check_vpn_v6_cidr "${addr}" "fe80::/10" && return 1
    check_vpn_v6_cidr "${addr}" "::1/128" && return 1
    return 0
}

write_vpn_wg_runtime() {
    local src="$1" dest="$2" endpoint="$3"
    local line trimmed section="" key wrote_table=0 wrote_allowed=0 wrote_endpoint=0
    : > "${dest}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        trimmed="$(strip_vpn_text "${line}")"
        if [[ "${trimmed}" == \[*\] ]]; then
            if [[ "${section}" == "Interface" && "${wrote_table}" -eq 0 ]]; then
                printf 'Table = off\n' >> "${dest}"
            fi
            if [[ "${section}" == "Peer" ]]; then
                [[ "${wrote_allowed}" -eq 1 ]] || printf 'AllowedIPs = 0.0.0.0/0, ::/0\n' >> "${dest}"
                [[ "${wrote_endpoint}" -eq 1 ]] || printf 'Endpoint = %s\n' "${endpoint}" >> "${dest}"
            fi
            section="${trimmed#[}"
            section="${section%]}"
            wrote_table=0
            wrote_allowed=0
            wrote_endpoint=0
            printf '%s\n' "${trimmed}" >> "${dest}"
            continue
        fi
        key="${trimmed%%=*}"
        key="$(strip_vpn_text "${key}")"
        case "${section}" in
            Interface)
                if [[ "${key}" == "Table" ]]; then
                    printf 'Table = off\n' >> "${dest}"
                    wrote_table=1
                    continue
                fi
                [[ "${key}" == "DNS" ]] && continue
                printf '%s\n' "${line}" >> "${dest}"
                ;;
            Peer)
                if [[ "${key}" == "AllowedIPs" ]]; then
                    printf 'AllowedIPs = 0.0.0.0/0, ::/0\n' >> "${dest}"
                    wrote_allowed=1
                    continue
                fi
                if [[ "${key}" == "Endpoint" ]]; then
                    printf 'Endpoint = %s\n' "${endpoint}" >> "${dest}"
                    wrote_endpoint=1
                    continue
                fi
                printf '%s\n' "${line}" >> "${dest}"
                ;;
            *)
                printf '%s\n' "${line}" >> "${dest}"
                ;;
        esac
    done < "${src}"
    if [[ "${section}" == "Interface" && "${wrote_table}" -eq 0 ]]; then
        printf 'Table = off\n' >> "${dest}"
    fi
    if [[ "${section}" == "Peer" ]]; then
        [[ "${wrote_allowed}" -eq 1 ]] || printf 'AllowedIPs = 0.0.0.0/0, ::/0\n' >> "${dest}"
        [[ "${wrote_endpoint}" -eq 1 ]] || printf 'Endpoint = %s\n' "${endpoint}" >> "${dest}"
    fi
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

install_vpn_openvpn() {
    local name="$1" src="$2" work dir base line trimmed key rest token path copied
    local in_tag=0 proto="udp" port="1194" remote_count=0 host="" rport="" rproto=""
    local ep4="" ep6="" pinned="" chosen="" enc=0 extra=0
    local -a rows=()
    check_vpn_import_name "${name}" || return 1
    [[ -f "${src}" ]] || log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.missing" "${name}"
    load_vpn_settings
    dir="$(cd -- "$(dirname -- "${src}")" && pwd)"
    work="$(mktemp -d "$(get_vpn_home)/.import.XXXXXX")"
    chmod 700 "${work}"
    cp -a "${src}" "${work}/source"
    chmod 600 "${work}/source"
    : > "${work}/runtime"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        trimmed="$(strip_vpn_text "${line}")"
        if [[ "${in_tag}" -eq 1 ]]; then
            printf '%s\n' "${line}" >> "${work}/runtime"
            [[ "${trimmed}" == \</*\> ]] && in_tag=0
            continue
        fi
        if [[ "${trimmed}" == \<* && "${trimmed}" != \</*\> && "${trimmed}" != *\>* ]]; then
            in_tag=1
            printf '%s\n' "${line}" >> "${work}/runtime"
            continue
        fi
        [[ -z "${trimmed}" || "${trimmed}" == \#* || "${trimmed}" == \;* ]] && {
            printf '%s\n' "${line}" >> "${work}/runtime"
            continue
        }
        key="${trimmed%%[[:space:]]*}"
        rest="${trimmed#"${key}"}"
        rest="$(strip_vpn_text "${rest}")"
        case "${key}" in
            proto)
                proto="$(get_vpn_ovpn_token "${rest}")"
                printf '%s\n' "${line}" >> "${work}/runtime"
                ;;
            port)
                port="$(get_vpn_ovpn_token "${rest}")"
                printf '%s\n' "${line}" >> "${work}/runtime"
                ;;
            remote)
                remote_count=$((remote_count + 1))
                if (( remote_count > 1 )); then
                    extra=1
                    continue
                fi
                read -r host rport rproto <<< "${rest}"
                host="$(get_vpn_ovpn_token "${host}")"
                if [[ "${rport:-}" =~ ^(udp|tcp) ]]; then
                    rproto="${rport}"
                    rport=""
                fi
                [[ -n "${rport:-}" ]] && port="$(get_vpn_ovpn_token "${rport}")"
                [[ -n "${rproto:-}" ]] && proto="$(get_vpn_ovpn_token "${rproto}")"
                printf 'REMOTE %s\n' "${host}" >> "${work}/runtime"
                ;;
            auth-user-pass)
                token="$(get_vpn_ovpn_token "${rest}")"
                if [[ -z "${token}" ]]; then
                    rm -rf "${work}"
                    log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.auth"
                fi
                path="${token}"
                [[ "${path}" == /* ]] || path="${dir}/${path}"
                [[ -f "${path}" ]] || {
                    rm -rf "${work}"
                    log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.missing" "${name}"
                }
                cp -a "${path}" "${work}/auth.txt"
                chmod 600 "${work}/auth.txt"
                printf 'auth-user-pass auth.txt\n' >> "${work}/runtime"
                ;;
            ca|cert|key|tls-crypt|tls-auth|tls-crypt-v2|dh|pkcs12|secret)
                read -r token extra <<< "${rest}"
                token="$(get_vpn_ovpn_token "${token}")"
                [[ -n "${token}" ]] || {
                    printf '%s\n' "${line}" >> "${work}/runtime"
                    continue
                }
                path="${token}"
                [[ "${path}" == /* ]] || path="${dir}/${path}"
                [[ -f "${path}" ]] || {
                    rm -rf "${work}"
                    log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.missing" "${name}"
                }
                copied="$(basename -- "${path}")"
                if [[ -e "${work}/${copied}" ]]; then
                    copied="${key}-${copied}"
                fi
                cp -a "${path}" "${work}/${copied}"
                chmod 600 "${work}/${copied}"
                if [[ -n "${extra}" ]]; then
                    printf '%s %s %s\n' "${key}" "${copied}" "${extra}" >> "${work}/runtime"
                else
                    printf '%s %s\n' "${key}" "${copied}" >> "${work}/runtime"
                fi
                ;;
            dev|dev-type)
                continue
                ;;
            *)
                printf '%s\n' "${line}" >> "${work}/runtime"
                ;;
        esac
    done < "${work}/source"
    if [[ -z "${host}" ]]; then
        rm -rf "${work}"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.missing" "${name}"
    fi
    case "${proto}" in
        udp|udp4|udp6) proto="udp" ;;
        tcp|tcp4|tcp6|tcp-client|tcp-server) proto="tcp" ;;
        *)
            rm -rf "${work}"
            log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.missing" "${name}"
            ;;
    esac
    [[ "${port}" =~ ^[0-9]+$ ]] || {
        rm -rf "${work}"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.missing" "${name}"
    }
    mapfile -t rows < <(get_vpn_host "${host}" || true)
    if (( ${#rows[@]} == 0 )); then
        rm -rf "${work}"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.dns" "${host}"
    fi
    for line in "${rows[@]}"; do
        if [[ "${line}" == 4\ * ]]; then
            ep4+="${ep4:+ }${line#4 }"
        else
            ep6+="${ep6:+ }${line#6 }"
        fi
    done
    if [[ -n "${ep4}" ]]; then
        pinned="${ep4%% *}"
    else
        pinned="${ep6%% *}"
    fi
    sed -i "s|^REMOTE .*|remote ${pinned} ${port} ${proto}|" "${work}/runtime"
    printf 'dev %s\ndev-type tun\n' "${W_VPN_IFACE_OVPN}" >> "${work}/runtime"
    chmod 600 "${work}/runtime"
    if grep -q 'ENCRYPTED' "${work}/source" "${work}/runtime" "${work}"/* 2>/dev/null; then
        enc=1
    fi
    write_vpn_meta "${work}" openvpn "${ep4}" "${ep6}" "${port}" "${proto}" "${W_VPN_IFACE_OVPN}" 0 "${enc}"
    if (( extra == 1 )) && declare -F log_info >/dev/null 2>&1; then
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.import.remote" "${pinned}"
    fi
    finish_vpn_import "${work}" "${name}" "${pinned}" openvpn
}

refresh_vpn_endpoint() {
    local name="$1" proto host port ep4="" ep6="" line pinned chosen
    local -a rows=()
    local dir runtime
    check_vpn_name "${name}" || log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.bad-name" "${name}"
    [[ -f "$(get_vpn_profile_dir "${name}")/meta" ]] || log_error "${INSTALL_WATCHER:-BASH}" "vpn.rm.missing" "${name}"
    proto="$(get_vpn_meta "${name}" proto)"
    port="$(get_vpn_meta "${name}" port)"
    dir="$(get_vpn_profile_dir "${name}")"
    runtime="${dir}/runtime"
    if [[ "${proto}" == "wireguard" ]]; then
        host="$(awk -F= '/^[[:space:]]*Endpoint[[:space:]]*=/{print $2; exit}' "${dir}/source")"
        host="$(strip_vpn_text "${host}")"
        read -r host port < <(get_vpn_wg_endpoint "${host}") || log_error "${INSTALL_WATCHER:-BASH}" "vpn.refresh.fail" "${name}"
    else
        host="$(awk '/^[[:space:]]*remote[[:space:]]/{print $2; exit}' "${dir}/source")"
        host="$(get_vpn_ovpn_token "${host}")"
    fi
    if get_vpn_ipv4_parts "${host}" >/dev/null 2>&1 || get_vpn_v6_groups "${host}" >/dev/null 2>&1; then
        log_success "${INSTALL_WATCHER:-BASH}" "vpn.refresh.ok" "${name}" "${host}"
        return 0
    fi
    mapfile -t rows < <(get_vpn_host "${host}" || true)
    if (( ${#rows[@]} == 0 )); then
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.refresh.fail" "${name}"
    fi
    for line in "${rows[@]}"; do
        if [[ "${line}" == 4\ * ]]; then
            ep4+="${ep4:+ }${line#4 }"
        else
            ep6+="${ep6:+ }${line#6 }"
        fi
    done
    if [[ -n "${ep4}" ]]; then
        pinned="${ep4%% *}"
        chosen="${pinned}:${port}"
    else
        pinned="${ep6%% *}"
        chosen="[${pinned}]:${port}"
    fi
    write_vpn_meta "${dir}" "${proto}" "${ep4}" "${ep6}" "${port}" "$(get_vpn_meta "${name}" transport)" "$(get_vpn_meta "${name}" iface)" "$(get_vpn_meta "${name}" has_ipv6)" "$(get_vpn_meta "${name}" encrypted)"
    if [[ "${proto}" == "wireguard" ]]; then
        sed -i "s|^[[:space:]]*Endpoint[[:space:]]*=.*|Endpoint = ${chosen}|" "${runtime}"
    else
        sed -i "s|^[[:space:]]*remote[[:space:]].*|remote ${pinned} ${port} $(get_vpn_meta "${name}" transport)|" "${runtime}"
    fi
    chmod 600 "${runtime}" "${dir}/meta"
    if [[ "$(get_vpn_active 2>/dev/null || true)" == "${name}" ]]; then
        apply_vpn_endpoint_routes "${name}"
        apply_vpn_nft "${name}" 1
        log_success "${INSTALL_WATCHER:-BASH}" "vpn.refresh.active" "${name}"
    fi
    log_success "${INSTALL_WATCHER:-BASH}" "vpn.refresh.ok" "${name}" "${pinned}"
}
