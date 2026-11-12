#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/arm.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

# -----------------------------------------------------------------------------
# Purpose    : Enable the timers, then start them after the reference databases exist.
# Note       : enable.sh calls this script with enable. The install plan calls it to start.
# Note       : The boot timer has a zero delay and starts the first pass.
# -----------------------------------------------------------------------------

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
arm_mode="${4:-start}"
export INSTALL_WATCHER INSTALL_DIRECTORY

# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
require_root

case "${arm_mode}" in
    enable)
        log_info "${INSTALL_WATCHER}" "configure.watchdog-enable-timers"
        run_silent "${INSTALL_WATCHER}" "configure.cron.error.8" systemctl daemon-reload
        run_silent "${INSTALL_WATCHER}" "configure.cron.error.9" systemctl enable w-boot-chain.timer
        run_silent "${INSTALL_WATCHER}" "configure.cron.error.10" systemctl enable w-idle-scan.timer
        run_silent "${INSTALL_WATCHER}" "configure.cron.error.11" systemctl enable w-reboot-notice.timer
        run_silent "${INSTALL_WATCHER}" "configure.cron.error.12" systemctl enable w-periodic-scan.timer
        run_silent "${INSTALL_WATCHER}" "configure.cron.error.13" systemctl enable w-hourly-scan.timer
        log_success "${INSTALL_WATCHER}" "configure.watchdog-timers-armed"
        ;;
    start)
        run_silent "${INSTALL_WATCHER}" "configure.cron.error.9" systemctl start w-boot-chain.timer
        run_silent "${INSTALL_WATCHER}" "configure.cron.error.10" systemctl start w-idle-scan.timer
        run_silent "${INSTALL_WATCHER}" "configure.cron.error.11" systemctl start w-reboot-notice.timer
        run_silent "${INSTALL_WATCHER}" "configure.cron.error.12" systemctl start w-periodic-scan.timer
        run_silent "${INSTALL_WATCHER}" "configure.cron.error.13" systemctl start w-hourly-scan.timer
        log_info "${INSTALL_WATCHER}" "configure.watchdog-first-pass"
        ;;
esac
