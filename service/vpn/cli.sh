#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/cli.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Run one named tunnel command.
# Note       : Removing the active default profile starts the successor.
# -----------------------------------------------------------------------------


load_vpn_cli() {
    set -euo pipefail
    VPN_SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    ROOT="$(cd -- "${VPN_SRC}/../.." && pwd)"
    export PRODUCT_ROOT="${ROOT}"
    export INSTALL_DIRECTORY="${ROOT}"
    INSTALL_WATCHER="${INSTALL_WATCHER:-BASH}"
    export INSTALL_WATCHER
    # shellcheck disable=SC1091
    source "${ROOT}/core/boot/lib.sh"
    # shellcheck disable=SC1091
    source "${ROOT}/config/global.conf"
    # shellcheck disable=SC1091
    source "${VPN_SRC}/lib.sh"
    # shellcheck disable=SC1091
    source "${VPN_SRC}/state.sh"
    # shellcheck disable=SC1091
    source "${VPN_SRC}/killswitch.sh"
    # shellcheck disable=SC1091
    source "${VPN_SRC}/routes.sh"
    # shellcheck disable=SC1091
    source "${VPN_SRC}/import.sh"
    # shellcheck disable=SC1091
    source "${VPN_SRC}/nm.sh"
    # shellcheck disable=SC1091
    source "${VPN_SRC}/up.sh"
    # shellcheck disable=SC1091
    source "${VPN_SRC}/down.sh"
    # shellcheck disable=SC1091
    source "${VPN_SRC}/switch.sh"
    # shellcheck disable=SC1091
    source "${VPN_SRC}/failover.sh"
    require_root
    load_vpn_settings
}

show_vpn_usage() {
    printf '%s\n' "$(get_text vpn.usage)" >&2
    exit 2
}

# An empty name, a rejected name, or a missing profile ends the command.
validate_vpn_remove() {
    local name="$1"
    [[ -n "${name}" ]] || show_vpn_usage
    if ! check_vpn_name "${name}"; then
        record_vpn_log rm "${name}" fail "bad-name"
        log_error "${INSTALL_WATCHER}" "vpn.import.bad-name" "${name}"
    fi
    if [[ ! -d "$(get_vpn_profile_directory "${name}")" || ! -f "$(get_vpn_profile_directory "${name}")/meta" ]]; then
        record_vpn_log rm "${name}" fail "missing"
        log_error "${INSTALL_WATCHER}" "vpn.rm.missing" "${name}"
    fi
}

# An active profile that is not the default cannot be removed.
fail_vpn_remove_active() {
    local name="$1" active="$2" total="$3"
    if [[ "${active}" == "${name}" && "${total}" != "1" && "${VPN_DEFAULT:-}" != "${name}" ]]; then
        record_vpn_log rm "${name}" fail "active"
        log_error "${INSTALL_WATCHER}" "vpn.rm.active" "${name}"
    fi
}

remove_vpn_profile() {
    local name="${1:-}" active total was_active=0
    local -a successors=()
    validate_vpn_remove "${name}"
    load_vpn_settings
    active="$(get_vpn_active 2>/dev/null || true)"
    total="$(get_vpn_profile_count)"
    fail_vpn_remove_active "${name}" "${active}" "${total}"
    if [[ "${VPN_DEFAULT:-}" == "${name}" && "${total}" != "1" ]]; then
        mapfile -t successors < <(list_vpn_successors "${name}")
        if [[ "${active}" == "${name}" ]]; then
            was_active=1
        fi
        VPN_DEFER_INTEGRITY=1
        clear_vpn_profile "${name}" "rm"
        VPN_DEFER_INTEGRITY=0
        run_vpn_successor "${was_active}" "${successors[@]}" || true
        refresh_vpn_integrity
        return 0
    fi
    clear_vpn_profile "${name}" "rm"
}

show_vpn_default() {
    load_vpn_settings
    if [[ -n "${VPN_DEFAULT:-}" ]]; then
        printf '%s\n' "$(get_text vpn.status.default "${VPN_DEFAULT}")"
        return 0
    fi
    printf '%s\n' "$(get_text vpn.status.default-none)"
}

set_vpn_default() {
    local name="${1:-}"
    [[ -n "${name}" ]] || show_vpn_usage
    if ! check_vpn_name "${name}"; then
        record_vpn_log default "${name}" fail "bad-name"
        log_error "${INSTALL_WATCHER}" "vpn.import.bad-name" "${name}"
    fi
    if [[ ! -f "$(get_vpn_profile_directory "${name}")/meta" ]]; then
        record_vpn_log default "${name}" fail "missing"
        log_error "${INSTALL_WATCHER}" "vpn.default.missing" "${name}"
    fi
    if ! check_vpn_profile_valid "${name}"; then
        record_vpn_log default "${name}" fail "invalid"
        log_error "${INSTALL_WATCHER}" "vpn.default.invalid" "${name}"
    fi
    set_vpn_state_default "${name}"
    load_vpn_settings
    apply_vpn_systemd || {
        record_vpn_log default "${name}" fail "install"
        log_error "${INSTALL_WATCHER}" "vpn.install.fail"
    }
    apply_vpn_default_autoconnect
    refresh_vpn_integrity
    record_vpn_log default "${name}" ok ""
    log_success "${INSTALL_WATCHER}" "vpn.default.set" "${name}"
}

# NetworkManager follows the new default when that tool is present.
apply_vpn_default_autoconnect() {
    if declare -F apply_vpn_nm_autoconnect >/dev/null 2>&1; then
        apply_vpn_nm_autoconnect || true
    fi
}

clear_vpn_default() {
    local previous
    load_vpn_settings
    previous="${VPN_DEFAULT:-}"
    set_vpn_state_default ""
    load_vpn_settings
    apply_vpn_systemd || true
    if declare -F apply_vpn_nm_autoconnect >/dev/null 2>&1; then
        apply_vpn_nm_autoconnect || true
    fi
    refresh_vpn_integrity
    record_vpn_log default "${previous:-"-"}" ok "off"
    log_success "${INSTALL_WATCHER}" "vpn.default.cleared"
}

# The profile line keeps the saved handshake when that file exists.
show_vpn_profile_line() {
    local name="$1"
    local proto="" iface="" handshake="-"
    if [[ -n "${name}" && -f "$(get_vpn_profile_directory "${name}")/meta" ]]; then
        proto="$(get_vpn_meta "${name}" proto 2>/dev/null || true)"
        iface="$(get_vpn_meta "${name}" iface 2>/dev/null || true)"
        if [[ -f "$(get_vpn_profile_directory "${name}")/handshake" ]]; then
            handshake="$(tr -d '[:space:]' <"$(get_vpn_profile_directory "${name}")/handshake")"
        fi
        printf '%s\n' "$(get_text vpn.status.line "${name}" "${proto}" "${iface}" "${handshake}")"
    else
        printf '%s\n' "$(get_text vpn.status.none)"
    fi
}

# A live tunnel reports success. An armed idle state reports a failure.
finish_vpn_status() {
    local name="$1"
    local armed="$2"
    local code=0
    if [[ -n "${name}" ]] && check_vpn_tunnel "${name}"; then
        code=0
    elif [[ "${armed}" -eq 1 ]]; then
        code=1
    fi
    exit "${code}"
}

show_vpn_status() {
    local armed=0 name count mode
    load_vpn_settings
    mode="${VPN_MODE:-off}"
    printf '%s\n' "$(get_text vpn.status.mode "${mode}")"
    if [[ -n "${VPN_DEFAULT:-}" ]]; then
        printf '%s\n' "$(get_text vpn.status.default "${VPN_DEFAULT}")"
    else
        printf '%s\n' "$(get_text vpn.status.default-none)"
    fi
    if check_vpn_killswitch; then
        armed=1
        printf '%s\n' "$(get_text vpn.status.armed)"
    else
        printf '%s\n' "$(get_text vpn.status.disarmed)"
    fi
    name="$(get_vpn_active 2>/dev/null || true)"
    if [[ -z "${name}" && "${armed}" -eq 1 ]]; then
        name="${VPN_BOOT_PROFILE:-}"
    fi
    show_vpn_profile_line "${name}"
    if [[ "${armed}" -eq 1 ]]; then
        count="$(get_vpn_bypass_count)"
        printf '%s\n' "$(get_text vpn.status.bypass "${count}")"
    fi
    finish_vpn_status "${name}" "${armed}"
}

list_vpn_profiles() {
    local home directory name proto found=0 kind valid validated observed tested state brand
    home="$(get_vpn_home)"
    refresh_vpn_state
    shopt -s nullglob
    for kind in wireguard openvpn profiles; do
        for directory in "${home}/${kind}"/*/; do
            [[ -d "${directory}" ]] || continue
            name="$(basename -- "${directory}")"
            check_vpn_name "${name}" || continue
            proto="$(get_vpn_meta "${name}" proto 2>/dev/null || echo "${kind}")"
            valid="false"
            validated=""
            observed=""
            tested=""
            if state="$(show_vpn_profile_state "${name}" 2>/dev/null)"; then
                valid="$(printf '%s\n' "${state}" | sed -n '1p')"
                validated="$(printf '%s\n' "${state}" | sed -n '2p')"
                observed="$(printf '%s\n' "${state}" | sed -n '3p')"
                tested="$(printf '%s\n' "${state}" | sed -n '4p')"
            fi
            brand="$(get_vpn_meta "${name}" brand 2>/dev/null || true)"
            printf '%s  %s\n' "$(get_text vpn.list.line "${name}" "${proto}" "${valid}" "${validated}" "${observed}" "${tested}" "${brand}")" "${directory%/}"
            found=1
        done
    done
    shopt -u nullglob
    if ((found == 0)); then
        printf '%s\n' "$(get_text vpn.list.empty)"
    fi
}

show_vpn_bypass() {
    local file line
    file="$(get_vpn_home)/bypass.cidrs"
    printf '%s\n' "$(get_text vpn.bypass.head "${file}")"
    if [[ -f "${file}" ]]; then
        cat "${file}"
    fi
    while IFS= read -r line; do
        printf '%s\n' "$(get_text vpn.bypass.implicit "${line}")"
    done < <(list_vpn_implicit)
    printf '%s\n' "$(get_text vpn.bypass.implicit "DHCP 68:67 546:547")"
}

run_vpn_bypass_reload() {
    local home="${1:-}"
    home="$(get_vpn_home)"
    if [[ ! -f "${home}/bypass.cidrs" ]]; then
        log_error "${INSTALL_WATCHER}" "vpn.bypass.bad" "${home}/bypass.cidrs"
    fi
    if ! write_vpn_bypass "${home}/bypass.cidrs" "${home}/bypass.applied"; then
        log_error "${INSTALL_WATCHER}" "vpn.bypass.kept"
    fi
    if check_vpn_killswitch; then
        apply_vpn_bypass_routes
        if [[ -n "$(get_vpn_active 2>/dev/null || true)" ]]; then
            apply_vpn_nft "$(get_vpn_active)" 1
        elif check_vpn_boot_on; then
            apply_vpn_nft "${VPN_BOOT_PROFILE}" 0
        else
            apply_vpn_nft "" 0
        fi
    fi
    refresh_vpn_integrity
    log_success "${INSTALL_WATCHER}" "vpn.bypass.reloaded"
}

arm_vpn_boot() {
    load_vpn_settings
    if ! check_vpn_boot_on; then
        set_vpn_state_mode off
        load_vpn_settings
        apply_vpn_systemd || true
        clear_vpn_network
        refresh_vpn_integrity
        log_info "${INSTALL_WATCHER}" "vpn.direct.ok"
        exit 0
    fi
    apply_vpn_nft "" 0 || true
    apply_vpn_bypass_routes || true
    exit 0
}

run_vpn_cli_status() {
    [[ $# -eq 0 ]] || show_vpn_usage
    show_vpn_status
}

run_vpn_cli_list() {
    [[ $# -eq 0 ]] || show_vpn_usage
    list_vpn_profiles
}

run_vpn_cli_import() {
    [[ $# -eq 4 ]] || show_vpn_usage
    case "$1" in
        wireguard | openvpn) install_vpn_bundle "$1" "$2" "$3" "$4" ;;
        *) show_vpn_usage ;;
    esac
}

run_vpn_cli_test() {
    local test_rc=0
    [[ $# -eq 1 ]] || show_vpn_usage
    run_vpn_test "$1" || test_rc=$?
    refresh_vpn_integrity
    exit "${test_rc}"
}

run_vpn_cli_switch() {
    [[ $# -eq 1 ]] || show_vpn_usage
    run_vpn_switch "$1"
}

run_vpn_cli_mode() {
    [[ $# -eq 1 ]] || show_vpn_usage
    case "$1" in
        on) run_vpn_mode_on ;;
        off) run_vpn_mode_off ;;
        *) show_vpn_usage ;;
    esac
}

run_vpn_cli_default() {
    if [[ $# -eq 0 ]]; then
        show_vpn_default
    elif [[ $# -eq 1 && "$1" == "off" ]]; then
        clear_vpn_default
    elif [[ $# -eq 1 ]]; then
        set_vpn_default "$1"
    else
        show_vpn_usage
    fi
}

run_vpn_cli_remove() {
    [[ $# -eq 1 ]] || show_vpn_usage
    remove_vpn_profile "$1"
}

run_vpn_cli_bypass() {
    if [[ $# -eq 0 ]]; then
        show_vpn_bypass
    elif [[ $# -eq 1 && "$1" == "reload" ]]; then
        run_vpn_bypass_reload
    else
        show_vpn_usage
    fi
}

run_vpn_cli_endpoint() {
    [[ $# -eq 1 ]] || show_vpn_usage
    refresh_vpn_endpoint "$1"
}

run_vpn_cli_boot() {
    load_vpn_settings
    if ! check_vpn_boot_on; then
        set_vpn_state_mode off
        load_vpn_settings
        apply_vpn_systemd || true
        clear_vpn_network
        refresh_vpn_integrity
        exit 0
    fi
    if check_vpn_tunnel "${VPN_BOOT_PROFILE}"; then
        exit 0
    fi
    VPN_DEFER_INTEGRITY=1
    run_vpn_failover
    VPN_DEFER_INTEGRITY=0
    refresh_vpn_integrity
    exit 0
}

load_vpn_cli

cmd="${1:-}"
shift || true

case "${cmd}" in
    status) run_vpn_cli_status "$@" ;;
    list) run_vpn_cli_list "$@" ;;
    import) run_vpn_cli_import "$@" ;;
    test) run_vpn_cli_test "$@" ;;
    switch) run_vpn_cli_switch "$@" ;;
    mode) run_vpn_cli_mode "$@" ;;
    default) run_vpn_cli_default "$@" ;;
    rm) run_vpn_cli_remove "$@" ;;
    bypass) run_vpn_cli_bypass "$@" ;;
    refresh-endpoint) run_vpn_cli_endpoint "$@" ;;
    boot-killswitch) arm_vpn_boot ;;
    boot-up) run_vpn_cli_boot ;;
    *) show_vpn_usage ;;
esac
