#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/state.sh
# Updated at : 2026-11-05
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

get_vpn_state_path() {
    printf '%s/vpn.json\n' "$(get_vpn_home)"
}

run_vpn_state() {
    python3 "$(locate_python_dir)/vpn-state.py" "$@"
}

read_vpn_state() {
    local line
    VPN_MODE=off
    VPN_ACTIVE=
    line="$(run_vpn_state read "$(get_vpn_state_path)" 2>/dev/null || true)"
    VPN_MODE="${line%%$'\n'*}"
    if [[ "${line}" == *$'\n'* ]]; then
        VPN_ACTIVE="${line#*$'\n'}"
    fi
    VPN_ACTIVE="${VPN_ACTIVE//$'\n'/}"
    [[ "${VPN_MODE}" == "on" ]] || VPN_MODE=off
}

write_vpn_state() {
    local path
    path="$(get_vpn_state_path)"
    if [[ $# -eq 0 ]]; then
        run_vpn_state init "${path}"
        return 0
    fi
    run_vpn_state mode "${path}" "$1"
    if [[ $# -ge 2 ]]; then
        run_vpn_state active "${path}" "$2"
    fi
}

record_vpn_attempt() {
    local name="$1" flag="$2" proto
    proto="$(get_vpn_meta "${name}" proto 2>/dev/null || true)"
    [[ "${proto}" == "wireguard" || "${proto}" == "openvpn" ]] || proto="wireguard"
    run_vpn_state attempt "$(get_vpn_state_path)" "${name}" "${proto}" "${flag}"
}

record_vpn_status() {
    run_vpn_state observe "$(get_vpn_state_path)" "$1"
}

check_vpn_profile_valid() {
    run_vpn_state valid "$(get_vpn_state_path)" "$1"
}

check_vpn_any_valid() {
    run_vpn_state any-valid "$(get_vpn_state_path)"
}

check_vpn_had_valid() {
    run_vpn_state had-valid "$(get_vpn_state_path)"
}

list_vpn_failover_names() {
    run_vpn_state candidates "$(get_vpn_state_path)"
}

show_vpn_profile_state() {
    run_vpn_state show "$(get_vpn_state_path)" "$1"
}

remove_vpn_state() {
    run_vpn_state remove "$(get_vpn_state_path)" "$1"
}

set_vpn_state_mode() {
    run_vpn_state mode "$(get_vpn_state_path)" "$1"
}

set_vpn_state_active() {
    run_vpn_state active "$(get_vpn_state_path)" "$1"
}

refresh_vpn_state() {
    local home name proto kind dir
    local -a names=()
    home="$(get_vpn_home)"
    [[ -d "${home}" ]] || return 0
    shopt -s nullglob
    for kind in wireguard openvpn profiles; do
        for dir in "${home}/${kind}"/*/; do
            [[ -d "${dir}" ]] || continue
            name="$(basename -- "${dir}")"
            check_vpn_name "${name}" || continue
            proto="$(get_vpn_meta "${name}" proto 2>/dev/null || true)"
            [[ "${proto}" == "wireguard" || "${proto}" == "openvpn" ]] || proto="wireguard"
            run_vpn_state ensure "$(get_vpn_state_path)" "${name}" "${proto}"
            names+=("${name}")
        done
    done
    shopt -u nullglob
    if (( ${#names[@]} == 0 )); then
        run_vpn_state drop-missing "$(get_vpn_state_path)"
        return 0
    fi
    run_vpn_state drop-missing "$(get_vpn_state_path)" "${names[@]}"
}

restart_vpn_services() {
    local unit
    for unit in unbound.service systemd-resolved.service; do
        if systemctl cat "${unit}" >/dev/null 2>&1; then
            systemctl try-restart "${unit}" >/dev/null 2>&1 || true
        fi
    done
    if command -v resolvectl >/dev/null 2>&1; then
        resolvectl flush-caches >/dev/null 2>&1 || true
    fi
    if declare -F log_info >/dev/null 2>&1; then
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.service.restart"
    fi
}
