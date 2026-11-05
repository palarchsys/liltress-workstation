#!/usr/bin/env bash
# =============================================================================
# File       : core/verify.sh
# Updated at : 2026-11-05
# Creator    : palarchsys
# =============================================================================

report_section() {
    printf '\n===== %s =====\n' "$1"
}

record_fail() {
    FAIL=$((FAIL + 1))
    REASONS+=("ECHEC   $*")
}

record_warn() {
    WARN=$((WARN + 1))
    REASONS+=("A_VOIR  $*")
}

record_pass() {
    printf "$(get_text log.ok "$*")"
}

check_unit_word() {
    local unit="$1"
    local active
    active="$(systemctl is-active "${unit}" 2>/dev/null || true)"
    case "${active}" in
        active) printf "$(get_text log.ok-2)" ;;
        inactive|failed|activating|deactivating) printf "$(get_text log.inactive)" ;;
        *) printf "$(get_text log.absent)" ;;
    esac
}
