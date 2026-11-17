#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/state.sh
# Updated at : 2026-11-16
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Keep the saved tunnel mode, the active profile, and the default profile.
# Note       : A missing home directory leaves the saved rows in place.
# Note       : Installed resolvers are restarted after a flush.
# -----------------------------------------------------------------------------


# The caller owns shown_python and reads it after this call.
show_python_directory() {
    local candidate="$1"
    shown_python=0
    [[ -n "${candidate}" && -d "${candidate}" ]] || return 0
    (cd -- "${candidate}" && pwd -P)
    shown_python=1
    return 0
}

# The shared directory is printed as given, without resolving links.
show_share_python() {
    local dir="$1"
    shown_python=0
    if [[ ! -d "${dir}/share/python" ]]; then
        return 0
    fi
    printf '%s\n' "${dir}/share/python"
    shown_python=1
    return 0
}

locate_python_dir() {
    local dir="" hops=0 candidate="" shown_python=0
    for candidate in \
        "${CONFIG_BASE_DIRECTORY:-}/python" \
        "${BASE:-}/python" \
        "${INSTALL_DIRECTORY:-}/python" \
        "${INSTALL_DIRECTORY:-}/../share/python"; do
        show_python_directory "${candidate}"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
    done
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        show_share_python "${dir}"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
        show_python_directory "${dir}/python"
        if [[ "${shown_python}" -eq 1 ]]; then
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
    local line rest
    VPN_MODE=off
    VPN_ACTIVE=
    VPN_DEFAULT=
    line="$(run_vpn_state read "$(get_vpn_state_path)" 2>/dev/null || true)"
    VPN_MODE="${line%%$'\n'*}"
    rest=""
    if [[ "${line}" == *$'\n'* ]]; then
        rest="${line#*$'\n'}"
    fi
    VPN_ACTIVE="${rest%%$'\n'*}"
    if [[ "${rest}" == *$'\n'* ]]; then
        VPN_DEFAULT="${rest#*$'\n'}"
    fi
    VPN_DEFAULT="${VPN_DEFAULT%%$'\n'*}"
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

get_vpn_state_default() {
    local line
    line="$(run_vpn_state read "$(get_vpn_state_path)" 2>/dev/null || true)"
    printf '%s\n' "$(printf '%s\n' "${line}" | sed -n '3p')"
}

set_vpn_state_default() {
    run_vpn_state default "$(get_vpn_state_path)" "${1:-}"
}

# Any protocol other than the two known kinds is stored as wireguard.
get_vpn_state_protocol() {
    local proto
    proto="$(get_vpn_meta "$1" proto 2>/dev/null || true)"
    [[ "${proto}" == "wireguard" || "${proto}" == "openvpn" ]] || proto="wireguard"
    printf '%s\n' "${proto}"
    return 0
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
            proto="$(get_vpn_state_protocol "${name}")"
            run_vpn_state ensure "$(get_vpn_state_path)" "${name}" "${proto}"
            names+=("${name}")
        done
    done
    shopt -u nullglob
    if ((${#names[@]} == 0)); then
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
