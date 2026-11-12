#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/arm-units.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

# -----------------------------------------------------------------------------
# Purpose    : Enable the timers, then start them after the reference databases exist.
# Note       : The product script passes the unit names and the error keys.
# -----------------------------------------------------------------------------

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
arm_mode="${3:-start}"
daemon_key="${4:-}"
shift 4 || true
export INSTALL_WATCHER INSTALL_DIRECTORY

# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
require_root

arm_one() {
    local verb="$1"
    local unit="$2"
    local error_key="$3"
    run_silent "${INSTALL_WATCHER}" "${error_key}" systemctl "${verb}" "${unit}"
}

case "${arm_mode}" in
    enable)
        log_info "${INSTALL_WATCHER}" "configure.watchdog-enable-timers"
        if [[ -n "${daemon_key}" ]]; then
            run_silent "${INSTALL_WATCHER}" "${daemon_key}" systemctl daemon-reload
        fi
        for pair in "$@"; do
            arm_one enable "${pair%%:*}" "${pair#*:}"
        done
        log_success "${INSTALL_WATCHER}" "configure.watchdog-timers-armed"
        ;;
    start)
        for pair in "$@"; do
            arm_one start "${pair%%:*}" "${pair#*:}"
        done
        log_info "${INSTALL_WATCHER}" "configure.watchdog-first-pass"
        ;;
esac
