#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/import.sh
# Updated at : 2026-11-14
# Creator    : palarchsys
# =============================================================================


locate_python_dir() {
    local dir hops=0 candidate
    for candidate in \
        "${CONFIG_BASE_DIRECTORY:-}/python" \
        "${BASE:-}/python" \
        "${INSTALL_DIRECTORY:-}/python" \
        "${INSTALL_DIRECTORY:-}/../share/python"
    do
        if [[ -n "${candidate}" && -d "${candidate}" ]]; then
            (cd -- "${candidate}" && pwd -P)
            return 0
        fi
    done
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        if [[ -d "${dir}/share/python" ]]; then
            printf '%s\n' "${dir}/share/python"
            return 0
        fi
        if [[ -d "${dir}/python" ]]; then
            (cd -- "${dir}/python" && pwd -P)
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

get_vpn_dns() {
    local host="$1"
    python3 "$(locate_python_dir)/vpn-dns.py" "${host}" 127.0.0.1
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
    if [[ "${VPN_IMPORT_STAGE_ONLY:-0}" == "1" ]]; then
        VPN_STAGE_DIR="${work}"
        printf '%s\n' "${work}" > "$(get_vpn_home)/.stage-path"
        chmod 600 "$(get_vpn_home)/.stage-path"
        return 0
    fi
    dest="$(get_vpn_profile_dir "${name}" "${proto}")"
    mkdir -p "$(dirname -- "${dest}")"
    chmod 700 "$(dirname -- "${dest}")"
    chmod 700 "${work}"
    find "${work}" -type f -exec chmod 600 {} +
    mv "${work}" "${dest}"
    if declare -F run_vpn_test >/dev/null 2>&1; then
        if ! run_vpn_test "${name}"; then
            rm -rf "${dest}"
            if declare -F remove_vpn_state >/dev/null 2>&1; then
                remove_vpn_state "${name}"
            fi
            return 1
        fi
    fi
    if declare -F log_success >/dev/null 2>&1; then
        log_success "${INSTALL_WATCHER:-BASH}" "vpn.import.ok" "${name}" "${endpoint}"
    fi
}

install_vpn_wireguard() {
    local name="$1" src="$2" brand="${3:-}" work private line trimmed section=""
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
    if (( peers != 1 || has_private != 1 || has_public != 1 )) || [[ -z "${endpoint_line}" ]]; then
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
    write_vpn_meta "${work}" wireguard "${ep4}" "${ep6}" "${port}" udp "${VPN_IFACE_WG:-wg-liltress}" "${v6}" 0 "${brand}"
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

check_vpn_auth_file() {
    local file="$1" count=0 line
    [[ -f "${file}" ]] || return 0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        line="$(strip_vpn_text "${line}")"
        [[ -n "${line}" ]] || continue
        count=$((count + 1))
    done < "${file}"
    [[ "${count}" -ge 2 ]]
}

copy_vpn_material() {
    local key="$1" token="$2" extra="$3" dir="$4" work="$5"
    local path copied
    path="${token}"
    [[ "${path}" == /* ]] || path="${dir}/${path}"
    if [[ -d "${path}" ]]; then
        copied="${key}-dir"
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
        printf '%s %s %s\n' "${key}" "${copied}" "${extra}" >> "${work}/runtime"
    else
        printf '%s %s\n' "${key}" "${copied}" >> "${work}/runtime"
    fi
}

copy_vpn_auth() {
    local dir="$1" work="$2" token="$3"
    local path="" candidate
    if [[ -n "${token}" ]]; then
        path="${token}"
        [[ "${path}" == /* ]] || path="${dir}/${path}"
        [[ -f "${path}" ]] || return 1
        cp -a "${path}" "${work}/auth.txt"
    else
        for candidate in auth.txt credentials.txt login.txt pass.txt userpass.txt; do
            if [[ -f "${dir}/${candidate}" ]]; then
                cp -a "${dir}/${candidate}" "${work}/auth.txt"
                break
            fi
        done
        if [[ ! -f "${work}/auth.txt" ]]; then
            return 1
        fi
    fi
    if ! check_vpn_auth_file "${work}/auth.txt"; then
        return 1
    fi
    chmod 600 "${work}/auth.txt"
    printf 'auth-user-pass auth.txt\n' >> "${work}/runtime"
}

install_vpn_openvpn() {
    local name="$1" src="$2" brand="${3:-}" work dir base line trimmed key rest token path copied tail
    local in_tag=0 proto="udp" port="1194" remote_count=0 host="" rport="" rproto=""
    local ep4="" ep6="" pinned="" chosen="" enc=0 extra=0 auth_done=0
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
                if [[ "${auth_done}" -eq 1 ]]; then
                    continue
                fi
                token="$(get_vpn_ovpn_token "${rest}")"
                if ! copy_vpn_auth "${dir}" "${work}" "${token}"; then
                    rm -rf "${work}"
                    if [[ -n "${token}" ]]; then
                        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.missing" "${name}"
                    else
                        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.auth"
                    fi
                    return 1
                fi
                auth_done=1
                ;;
            ca|cert|key|tls-crypt|tls-auth|tls-crypt-v2|dh|pkcs12|secret|extra-certs|crl-verify|askpass)
                read -r token tail <<< "${rest}"
                token="$(get_vpn_ovpn_token "${token}")"
                [[ -n "${token}" ]] || {
                    printf '%s\n' "${line}" >> "${work}/runtime"
                    continue
                }
                tail="$(get_vpn_ovpn_token "${tail}")"
                if ! copy_vpn_material "${key}" "${token}" "${tail}" "${dir}" "${work}"; then
                    rm -rf "${work}"
                    log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.missing" "${name}"
                    return 1
                fi
                ;;
            dev|dev-type|up|down|route-up|route-pre-down|learn-address|comp-lzo|compress|redirect-gateway|redirect-private|dhcp-option)
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
    printf 'dev %s\ndev-type tun\n' "${VPN_IFACE_OVPN}" >> "${work}/runtime"
    chmod 600 "${work}/runtime"
    if grep -q 'ENCRYPTED' "${work}/source" "${work}/runtime" "${work}"/* 2>/dev/null; then
        enc=1
    fi
    write_vpn_meta "${work}" openvpn "${ep4}" "${ep6}" "${port}" "${proto}" "${VPN_IFACE_OVPN}" 0 "${enc}" "${brand}"
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
    write_vpn_meta "${dir}" "${proto}" "${ep4}" "${ep6}" "${port}" "$(get_vpn_meta "${name}" transport)" "$(get_vpn_meta "${name}" iface)" "$(get_vpn_meta "${name}" has_ipv6)" "$(get_vpn_meta "${name}" encrypted)" "$(get_vpn_meta "${name}" brand 2>/dev/null || true)"
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

vpn_brand_cited() {
    local ovpn="$1" line trimmed key rest token
    [[ -f "${ovpn}" ]] || return 0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        trimmed="$(strip_vpn_text "${line}")"
        [[ -z "${trimmed}" || "${trimmed}" == \#* || "${trimmed}" == \;* ]] && continue
        key="${trimmed%%[[:space:]]*}"
        rest="${trimmed#"${key}"}"
        rest="$(strip_vpn_text "${rest}")"
        case "${key}" in
            ca|cert|key|tls-crypt|tls-auth|tls-crypt-v2|dh|pkcs12|secret|extra-certs|crl-verify|askpass)
                token="$(get_vpn_ovpn_token "${rest}")"
                token="${token%%[[:space:]]*}"
                [[ -z "${token}" || "${token}" == \<* ]] && continue
                basename -- "${token}"
                ;;
        esac
    done < "${ovpn}"
}

vpn_brand_names() {
    local dir="$1" name base ovpn cited
    shift
    local -A allow=()
    for name in "$@"; do
        [[ -f "${dir}/${name}" ]] || return 2
        allow["${name}"]=1
    done
    ovpn=""
    if [[ -f "${dir}/config.ovpn" ]]; then
        ovpn="${dir}/config.ovpn"
    elif [[ -f "${dir}/openvpn.ovpn" ]]; then
        ovpn="${dir}/openvpn.ovpn"
    fi
    if [[ -n "${ovpn}" ]]; then
        while IFS= read -r cited; do
            [[ -n "${cited}" ]] && allow["${cited}"]=1
        done < <(vpn_brand_cited "${ovpn}")
    fi
    for name in "${dir}"/*; do
        [[ -e "${name}" ]] || continue
        base="$(basename -- "${name}")"
        [[ -n "${allow[${base}]+x}" ]] || return 2
        [[ -f "${name}" && ! -L "${name}" ]] || return 2
    done
    return 0
}

vpn_brand_plain() {
    local dir="$1" file
    for file in "${dir}"/*; do
        [[ -f "${file}" ]] || continue
        if grep -q 'REPLACE' "${file}"; then
            return 3
        fi
    done
    return 0
}

vpn_brand_openvpn() {
    local dir="$1"
    shift
    vpn_brand_names "${dir}" "$@" || return 2
    vpn_brand_plain "${dir}" || return 3
    check_vpn_auth_file "${dir}/auth.txt" || return 4
}

vpn_brand_wireguard() {
    local dir="$1"
    vpn_brand_names "${dir}" config.conf || return 2
    vpn_brand_plain "${dir}" || return 3
}

open_vpn_bundle() {
    local path="$1" dest="$2" name base
    if [[ -d "${path}" ]]; then
        for name in "${path}"/*; do
            [[ -e "${name}" ]] || continue
            [[ -L "${name}" || ! -f "${name}" ]] && return 1
            base="$(basename -- "${name}")"
            cp -a "${name}" "${dest}/${base}" || return 1
        done
        return 0
    fi
    [[ -f "${path}" ]] || return 1
    python3 - "${path}" "${dest}" << 'PY'
import os
import sys
import zipfile

src, dest = sys.argv[1], sys.argv[2]
try:
    archive = zipfile.ZipFile(src)
except zipfile.BadZipFile:
    sys.exit(1)
found = []
for info in archive.infolist():
    raw = info.filename.replace("\\", "/").strip("/")
    if not raw:
        continue
    if raw.startswith("/") or ".." in raw.split("/"):
        sys.exit(1)
    if "/" in raw:
        sys.exit(1)
    if info.file_size > 1048576:
        sys.exit(1)
    found.append((info, raw))
if not found or len(found) > 12:
    sys.exit(1)
for info, base in found:
    target = os.path.join(dest, base)
    with archive.open(info) as incoming, open(target, "wb") as outgoing:
        outgoing.write(incoming.read())
    os.chmod(target, 0o600)
PY
}

install_vpn_bundle() {
    local proto="$1" brand="$2" name="$3" path="$4"
    local dest src rc=0 stage_file
    check_vpn_import_name "${name}" || return 1
    if [[ ! -e "${path}" ]]; then
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.missing" "${name}"
        return 1
    fi
    dest="$(mktemp -d "$(get_vpn_home)/.bundle.XXXXXX")"
    chmod 700 "${dest}"
    if ! open_vpn_bundle "${path}" "${dest}"; then
        rm -rf "${dest}"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.shape" "${name}"
        return 1
    fi
    if ! declare -F "vpn_brand_${brand}" >/dev/null 2>&1; then
        rm -rf "${dest}"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.brand" "${brand}" "${proto}"
        return 1
    fi
    "vpn_brand_${brand}" "${proto}" "${dest}" || rc=$?
    if (( rc != 0 )); then
        rm -rf "${dest}"
        case "${rc}" in
            1) log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.brand" "${brand}" "${proto}" ;;
            3) log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.replace" "${name}" ;;
            4) log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.auth" ;;
            *) log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.shape" "${name}" ;;
        esac
        return 1
    fi
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
            log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.brand" "${brand}" "${proto}"
            return 1
            ;;
    esac
    stage_file="$(get_vpn_home)/.stage-path"
    rm -f "${stage_file}"
    (
        case "${proto}" in
            wireguard) install_vpn_wireguard "${name}" "${src}" "${brand}" ;;
            openvpn) install_vpn_openvpn "${name}" "${src}" "${brand}" ;;
        esac
    ) || rc=$?
    if [[ -f "${stage_file}" ]]; then
        VPN_STAGE_DIR="$(tr -d '[:space:]' < "${stage_file}")"
        rm -f "${stage_file}"
    fi
    rm -rf "${dest}"
    return "${rc}"
}

# shellcheck disable=SC1091
for VPN_BRAND_FILE in "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/brands/"*.sh; do
    [[ -f "${VPN_BRAND_FILE}" ]] || continue
    source "${VPN_BRAND_FILE}"
done
unset VPN_BRAND_FILE
