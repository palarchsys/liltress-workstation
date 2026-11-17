#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/switch.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Replace the active tunnel with another saved profile.
# Note       : A profile that is already running stays in place.
# -----------------------------------------------------------------------------


# The profile is taken down during the NetworkManager hold.
clear_vpn_switch_hold() {
    local name="$1"
    if declare -F vpn_nm_hold_on >/dev/null 2>&1; then
        vpn_nm_hold_on
        vpn_nm_set_autoconnect "${name}" false || true
        if [[ -z "${VPN_NM_DIR:-}" ]] && command -v nmcli >/dev/null 2>&1; then
            nmcli connection down id "${name}" >/dev/null 2>&1 || true
        fi
        vpn_nm_hold_off
    fi
}

fail_vpn_switch() {
    local name="$1" proto endpoint
    if declare -F vpn_nm_switch_off >/dev/null 2>&1; then
        vpn_nm_switch_off
    fi
    clear_vpn_switch_hold "${name}"
    proto="$(get_vpn_meta "${name}" proto 2>/dev/null || true)"
    endpoint="$(get_vpn_meta "${name}" endpoint4 2>/dev/null || true)"
    [[ -n "${endpoint}" ]] || endpoint="$(get_vpn_meta "${name}" endpoint6 2>/dev/null || true)"
    remove_vpn_iface "${name}"
    clear_vpn_tunnel_routes
    apply_vpn_nft "${name}" 0 || true
    clear_vpn_active
    send_vpn_alert "${name}" "${proto}" "${endpoint%% *}" "switch"
    restart_vpn_services
    if declare -F vpn_nm_apply_autoconnect >/dev/null 2>&1; then
        vpn_nm_apply_autoconnect || true
    fi
    if declare -F refresh_vpn_integrity >/dev/null 2>&1; then
        refresh_vpn_integrity || true
    fi
    note_vpn_log switch "${name}" fail "${proto}"
    log_error "${INSTALL_WATCHER:-BASH}" "vpn.switch.fail" "${name}"
}

# A bad name, a closed mode, or a missing runtime stops the change.
require_vpn_switch() {
    local name="$1"
    if ! check_vpn_name "${name}"; then
        note_vpn_log switch "${name}" fail "bad-name"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.import.bad-name" "${name}"
    fi
    if ! check_vpn_mode; then
        note_vpn_log switch "${name}" fail "mode"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.switch.mode"
    fi
    if ! check_vpn_profile_valid "${name}"; then
        note_vpn_log switch "${name}" fail "invalid"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.switch.invalid" "${name}"
    fi
    if [[ ! -f "$(get_vpn_profile_dir "${name}")/runtime" ]]; then
        note_vpn_log switch "${name}" fail "runtime"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.profile.invalid" "${name}"
    fi
    if check_vpn_encrypted "${name}" && ! check_vpn_passphrase; then
        note_vpn_log switch "${name}" fail "passphrase"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.up.agent" "${name}"
    fi
}

# The table is required before the profile starts.
require_vpn_switch_nft() {
    local name="$1"
    if ! apply_vpn_nft "${name}" 0; then
        if declare -F vpn_nm_switch_off >/dev/null 2>&1; then
            vpn_nm_switch_off
        fi
        note_vpn_log switch "${name}" fail "nft"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.profile.invalid" "${name}"
    fi
}

# A missing agent passphrase restores the table and stops.
fail_vpn_raised() {
    local name="$1"
    local raised="$2"
    if ((raised == 2)); then
        apply_vpn_nft "${name}" 0 || true
        note_vpn_log switch "${name}" fail "passphrase"
        log_error "${INSTALL_WATCHER:-BASH}" "vpn.up.agent" "${name}"
    fi
}

# The active profile is recorded, then the services and the integrity stamp follow.
finish_vpn_switch() {
    local name="$1"
    set_vpn_active "${name}"
    set_vpn_state_active "${name}"
    record_vpn_attempt "${name}" 1
    restart_vpn_services
    if declare -F vpn_nm_apply_autoconnect >/dev/null 2>&1; then
        vpn_nm_apply_autoconnect || true
    fi
    if declare -F refresh_vpn_integrity >/dev/null 2>&1; then
        refresh_vpn_integrity || true
    fi
    note_vpn_log switch "${name}" ok ""
    log_success "${INSTALL_WATCHER:-BASH}" "vpn.switch.ok" "${name}"
}

run_vpn_switch() {
    local name="$1" old raised=0
    load_vpn_settings
    require_vpn_switch "${name}"
    note_vpn_log switch "${name}" start ""
    old="$(get_vpn_active 2>/dev/null || true)"
    if [[ "${old}" == "${name}" ]] && check_vpn_tunnel "${name}"; then
        note_vpn_log switch "${name}" ok "same"
        log_success "${INSTALL_WATCHER:-BASH}" "vpn.up.same" "${name}"
        return 0
    fi
    if declare -F vpn_nm_switch_on >/dev/null 2>&1; then
        vpn_nm_switch_on
    fi
    require_vpn_switch_nft "${name}"
    clear_vpn_conntrack "${name}"
    apply_vpn_profile "${name}" || raised=$?
    if declare -F vpn_nm_switch_off >/dev/null 2>&1; then
        vpn_nm_switch_off
    fi
    fail_vpn_raised "${name}" "${raised}"
    if ((raised != 0)); then
        fail_vpn_switch "${name}"
    fi
    finish_vpn_switch "${name}"
}
