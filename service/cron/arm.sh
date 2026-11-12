#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/arm.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

# -----------------------------------------------------------------------------
# Purpose    : Arm the timers after the reference databases exist.
# Note       : The boot timer has a zero delay and starts the first pass.
# -----------------------------------------------------------------------------

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
require_root

log_info "${INSTALL_WATCHER}" "configure.watchdog-enable-timers"
run_silent "${INSTALL_WATCHER}" "configure.cron.error.8" systemctl daemon-reload
run_silent "${INSTALL_WATCHER}" "configure.cron.error.9" systemctl enable --now w-boot-chain.timer
run_silent "${INSTALL_WATCHER}" "configure.cron.error.10" systemctl enable --now w-idle-scan.timer
run_silent "${INSTALL_WATCHER}" "configure.cron.error.11" systemctl enable --now w-reboot-notice.timer
run_silent "${INSTALL_WATCHER}" "configure.cron.error.12" systemctl enable --now w-periodic-scan.timer
run_silent "${INSTALL_WATCHER}" "configure.cron.error.13" systemctl enable --now w-hourly-scan.timer
log_success "${INSTALL_WATCHER}" "configure.watchdog-timers-armed"
log_info "${INSTALL_WATCHER}" "configure.watchdog-first-pass"
