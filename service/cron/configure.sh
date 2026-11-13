#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/configure.sh
# Updated at : 2026-11-13
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

# shellcheck disable=SC2155
readonly DIR_SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root
get_current_user

cpu_quota="$(
    WATCHDOG_CPU_LIMIT="${WATCHDOG_CPU_LIMIT:-50}" \
        bash -c 'source "$1" && get_cpu_quota_percent' _ "${INSTALL_DIRECTORY}/core/watchdog/watchdog.sh"
)" || log_error        "${INSTALL_WATCHER}" "configure.quota-cpu-not-found"
[[ "${cpu_quota}" =~ ^[0-9]+$ ]] || log_error        "${INSTALL_WATCHER}" "configure.quota-cpu-invalid" "${cpu_quota:-vide}"
# shellcheck disable=SC1091
source "$(locate_config_file cron/timers.conf)"

log_info         "${INSTALL_WATCHER}" "configure.installation-of-the-watchdogs-chain-to-the-start" "${WATCHDOG_CPU_LIMIT}"
ensure_directory "${CONFIG_BASE_DIRECTORY}/cron" 750
ensure_directory "${CONFIG_BASE_DIRECTORY}/cron/cron_logs" 750
ensure_directory "${CONFIG_BASE_DIRECTORY}/cron/security_logs" 750
ensure_directory "${CONFIG_BASE_DIRECTORY}/cron/alerts" 750
rm -rf -- "${CONFIG_BASE_DIRECTORY}/cron/bin"
rm -f -- "${CONFIG_BASE_DIRECTORY}/cron/mail.conf"
if [[ -f "${CONFIG_BASE_DIRECTORY}/cron/rclone.conf" ]]; then
    chown root:root "${CONFIG_BASE_DIRECTORY}/cron/rclone.conf"
    chmod 600 "${CONFIG_BASE_DIRECTORY}/cron/rclone.conf"
fi

export PROJECT_SLUG CONFIG_BASE_DIRECTORY

sed "s|\${CONFIG_BASE_DIRECTORY}|${CONFIG_BASE_DIRECTORY}|g" "$(locate_config_file cron/schedule.cron)" \
    > "/etc/cron.d/${PROJECT_SLUG}"
chown root:root "/etc/cron.d/${PROJECT_SLUG}"
chmod 600 "/etc/cron.d/${PROJECT_SLUG}"

install -d -m 755 /etc/systemd/system
systemctl_bin="$(command -v systemctl || true)"
[[ -n "${systemctl_bin}" ]] || log_error        "${INSTALL_WATCHER}" "configure.systemctl-not-found"

render_unit() {
    local rel="$1"
    local src dest
    src="$(locate_config_file "cron/${rel}")" || log_error        "${INSTALL_WATCHER}" "configure.unit-absent" "${rel}"
    dest="/etc/systemd/system/${rel}"
    sed \
        -e "s|\\\${WATCHDOG_LIMIT_NICE}|${WATCHDOG_LIMIT_NICE}|g" \
        -e "s|\\\${cpu_quota}|${cpu_quota}|g" \
        -e "s|\\\${CONFIG_BASE_DIRECTORY}|${CONFIG_BASE_DIRECTORY}|g" \
        -e "s|\\\${systemctl_bin}|${systemctl_bin}|g" \
        -e "s|\\\${BOOT_ON_BOOT_SEC}|${BOOT_ON_BOOT_SEC}|g" \
        -e "s|\\\${BOOT_ACCURACY}|${BOOT_ACCURACY}|g" \
        -e "s|\\\${TIMER_PERSISTENT}|${TIMER_PERSISTENT}|g" \
        -e "s|\\\${IDLE_EVERY}|${IDLE_EVERY}|g" \
        -e "s|\\\${IDLE_ACCURACY}|${IDLE_ACCURACY}|g" \
        -e "s|\\\${REBOOT_EVERY}|${REBOOT_EVERY}|g" \
        -e "s|\\\${REBOOT_ACCURACY}|${REBOOT_ACCURACY}|g" \
        -e "s|\\\${PERIODIC_EVERY}|${PERIODIC_EVERY}|g" \
        -e "s|\\\${PERIODIC_ON_BOOT_SEC}|${PERIODIC_ON_BOOT_SEC}|g" \
        -e "s|\\\${PERIODIC_ACCURACY}|${PERIODIC_ACCURACY}|g" \
        -e "s|\\\${HOURLY_EVERY}|${HOURLY_EVERY}|g" \
        -e "s|\\\${HOURLY_ON_BOOT_SEC}|${HOURLY_ON_BOOT_SEC}|g" \
        -e "s|\\\${HOURLY_ACCURACY}|${HOURLY_ACCURACY}|g" \
        "${src}" > "${dest}"
    chmod 644 "${dest}"
}
render_unit w-boot-scan.service
render_unit w-boot-chain.service
render_unit w-boot-chain.timer
render_unit w-idle-scan.service
render_unit w-idle-scan.timer
render_unit w-reboot-notice.service
render_unit w-reboot-notice.timer
render_unit w-periodic-scan.service
render_unit w-periodic-scan.timer
render_unit w-hourly-scan.service
render_unit w-hourly-scan.timer
systemctl disable --now w-boot-scan.timer >/dev/null 2>&1 || true
rm -f /etc/systemd/system/w-boot-scan.timer
systemctl disable --now w-integrity.timer >/dev/null 2>&1 || true
systemctl disable --now w-integrity.service >/dev/null 2>&1 || true
rm -f /etc/systemd/system/w-integrity.timer /etc/systemd/system/w-integrity.service
systemctl disable --now w-behavior.timer >/dev/null 2>&1 || true
systemctl disable --now w-behavior.service >/dev/null 2>&1 || true
rm -f /etc/systemd/system/w-behavior.timer /etc/systemd/system/w-behavior.service
systemctl disable --now w-egress-watch.timer >/dev/null 2>&1 || true
systemctl disable --now w-egress-watch.service >/dev/null 2>&1 || true
rm -f /etc/systemd/system/w-egress-watch.timer /etc/systemd/system/w-egress-watch.service
run_silent       "${INSTALL_WATCHER}" "configure.cron.error.8" systemctl daemon-reload
log_success      "${INSTALL_WATCHER}" "configure.chain-of-start-hourly-password-and-scan-all-the-2" "${WATCHDOG_CPU_LIMIT}"

export BASE="${CONFIG_BASE_DIRECTORY}"
export SCAN_SKIP_HOME="${CURRENT_HOME}"
# shellcheck disable=SC1091
source "${DIR_SCRIPT_PATH}/watchdogs/scan-skip-lib.sh"
ensure_scan_skip_file "${CURRENT_HOME}"
if [[ ! -d /var/jeux ]]; then
    install -d -m 750 -o "${CURRENT_USER}" -g "${CURRENT_USER}" /var/jeux
fi
log_info         "${INSTALL_WATCHER}" "configure.watchdog-scan-skip"
bash "${CONFIG_BASE_DIRECTORY}/service/cron/watchdogs/apply-scan-skip.sh"
log_success      "${INSTALL_WATCHER}" "configure.watchdog-scan-skip-done"
set_tree_modes || log_error "${INSTALL_WATCHER}" "configure.secrets-conf-mode" "600"
log_info         "${INSTALL_WATCHER}" "configure.crontab-user-not-touch-no-cron-allow"
log_success      "${INSTALL_WATCHER}" "configure.watchdogs-installed-in-cron-bin" "${CONFIG_BASE_DIRECTORY}"
