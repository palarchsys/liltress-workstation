#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/configure.sh
# Updated at : 2026-11-12
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
log_info         "${INSTALL_WATCHER}" "configure.watchdog-copy-scripts"
ensure_directory "${CONFIG_BASE_DIRECTORY}/cron/bin" 755
ensure_directory "${CONFIG_BASE_DIRECTORY}/cron/cron_logs" 750
ensure_directory "${CONFIG_BASE_DIRECTORY}/cron/security_logs" 750
ensure_directory "${CONFIG_BASE_DIRECTORY}/cron/alerts" 750

cp -a --dereference --remove-destination "${DIR_SCRIPT_PATH}/watchdogs/." "${CONFIG_BASE_DIRECTORY}/cron/bin/"
chmod 750 "${CONFIG_BASE_DIRECTORY}/cron/bin/"*.sh
log_success      "${INSTALL_WATCHER}" "configure.watchdog-scripts-copied"
log_info         "${INSTALL_WATCHER}" "configure.watchdog-copy-catalogs"
source_core mail/mail.sh
install_mail_templates "${CONFIG_BASE_DIRECTORY}/cron/bin"
mail_src="$(readlink -f "${INSTALL_DIRECTORY}/core/mail/mail.sh")"
[[ -f "${mail_src}" ]] || log_error        "${INSTALL_WATCHER}" "configure.core-mail-sh-not-found-core-mail-sh" "${INSTALL_DIRECTORY}"
cp -f "${mail_src}" "${CONFIG_BASE_DIRECTORY}/cron/bin/mail.sh"
chmod 750 "${CONFIG_BASE_DIRECTORY}/cron/bin/mail.sh"
watch_src="$(readlink -f "${INSTALL_DIRECTORY}/core/watchdog/watchdog.sh")"
[[ -f "${watch_src}" ]] || log_error        "${INSTALL_WATCHER}" "configure.core-watchdog-sh-not-found" "${INSTALL_DIRECTORY}/core/watchdog/watchdog.sh"
cp -f "${watch_src}" "${CONFIG_BASE_DIRECTORY}/cron/bin/watchdog.sh"
chmod 750 "${CONFIG_BASE_DIRECTORY}/cron/bin/watchdog.sh"
advice_src="$(dirname -- "${watch_src}")/alert-advice.txt"
[[ -f "${advice_src}" ]] || log_error        "${INSTALL_WATCHER}" "configure.core-alert-advice-txt-not-found" "${advice_src}"
cp -f "${advice_src}" "${CONFIG_BASE_DIRECTORY}/cron/bin/alert-advice.txt"
chmod 644 "${CONFIG_BASE_DIRECTORY}/cron/bin/alert-advice.txt"

copy_runtime_file() {
    local src="$1" dest="$2" mode="$3" src_real="" dest_real=""
    [[ -f "${src}" ]] || log_error "${INSTALL_WATCHER}" "configure.core-watchdog-sh-not-found" "${src}"
    src_real="$(readlink -f "${src}")"
    if [[ -f "${dest}" ]]; then
        dest_real="$(readlink -f "${dest}" 2>/dev/null || true)"
        [[ "${src_real}" == "${dest_real}" ]] && return 0
    fi
    install -d -m 755 "$(dirname -- "${dest}")"
    install -m "${mode}" "${src_real}" "${dest}"
}

copy_runtime_file "${INSTALL_DIRECTORY}/core/log/log.sh" \
    "${CONFIG_BASE_DIRECTORY}/cron/bin/log.sh" 644
copy_runtime_file "${INSTALL_DIRECTORY}/core/text/text.sh" \
    "${CONFIG_BASE_DIRECTORY}/cron/bin/text.sh" 644
copy_runtime_file "${INSTALL_DIRECTORY}/core/log/display.sh" \
    "${CONFIG_BASE_DIRECTORY}/cron/bin/display.sh" 644
copy_runtime_file "${INSTALL_DIRECTORY}/core/log/journal.sh" \
    "${CONFIG_BASE_DIRECTORY}/cron/bin/journal.sh" 644
copy_runtime_file "${INSTALL_DIRECTORY}/core/log/log.sh" \
    "${CONFIG_BASE_DIRECTORY}/bin/log.sh" 644
copy_runtime_file "${INSTALL_DIRECTORY}/core/text/text.sh" \
    "${CONFIG_BASE_DIRECTORY}/bin/text.sh" 644
copy_runtime_file "${INSTALL_DIRECTORY}/core/log/display.sh" \
    "${CONFIG_BASE_DIRECTORY}/bin/display.sh" 644
copy_runtime_file "${INSTALL_DIRECTORY}/core/log/journal.sh" \
    "${CONFIG_BASE_DIRECTORY}/bin/journal.sh" 644
copy_runtime_file "${INSTALL_DIRECTORY}/core/text/text-load.sh" \
    "${CONFIG_BASE_DIRECTORY}/bin/text-load.sh" 644
copy_runtime_file "${INSTALL_DIRECTORY}/core/text/text-load.sh" \
    "${CONFIG_BASE_DIRECTORY}/cron/bin/text-load.sh" 644
copy_runtime_dir "${INSTALL_DIRECTORY}/../share/locale" \
    "${CONFIG_BASE_DIRECTORY}/locale"
exclude_src="$(locate_config_file alert/exclude.list || true)"
if [[ -n "${exclude_src}" && -f "${exclude_src}" ]]; then
    install -D -m 644 "$(readlink -f "${exclude_src}")" \
        "${CONFIG_BASE_DIRECTORY}/config/alert/exclude.list"
fi
log_success      "${INSTALL_WATCHER}" "configure.watchdog-catalogs-copied"
ignore_src="$(locate_config_file chkrootkit/patterns.ignore || true)"
if [[ -n "${ignore_src}" && -f "${ignore_src}" ]]; then
    install -m 644 "${ignore_src}" "${CONFIG_BASE_DIRECTORY}/cron/bin/chkrootkit.ignore"
fi

umask 077
cat > "${CONFIG_BASE_DIRECTORY}/cron/mail.conf" << EOF
MAIL_ALERTS="${MAIL_ALERTS:-0}"
WATCHDOG_MAIL="${WATCHDOG_MAIL:-}"
PROJECT_NAME="${PROJECT_NAME}"
MAIL_TEMPLATE="${MAIL_TEMPLATE:-mail.html}"
EOF
umask 022
chmod 600 "${CONFIG_BASE_DIRECTORY}/cron/mail.conf"
chown -R root:root "${CONFIG_BASE_DIRECTORY}/cron"
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
install -d -m 755 "${CONFIG_BASE_DIRECTORY}/bin"
install -m 755 "$(readlink -f "${INSTALL_DIRECTORY}/core/quarantine/restore.sh")" \
    "${CONFIG_BASE_DIRECTORY}/bin/quarantine-restore.sh"
install -m 755 "$(readlink -f "${INSTALL_DIRECTORY}/core/mail/mail-test.sh")" \
    "${CONFIG_BASE_DIRECTORY}/bin/mail-test.sh"
log_info         "${INSTALL_WATCHER}" "configure.watchdog-scan-skip"
bash "${CONFIG_BASE_DIRECTORY}/cron/bin/apply-scan-skip.sh"
log_success      "${INSTALL_WATCHER}" "configure.watchdog-scan-skip-done"

install -d -m 755 "${CONFIG_BASE_DIRECTORY}/config/integrity"
install -m 644 \
    "$(locate_config_file integrity/paths.list)" \
    "${CONFIG_BASE_DIRECTORY}/config/integrity/paths.list"
install -m 644 \
    "${INSTALL_DIRECTORY}/config/global.conf" \
    "${CONFIG_BASE_DIRECTORY}/config/global.conf"
export BASE="${CONFIG_BASE_DIRECTORY}"
log_info         "${INSTALL_WATCHER}" "configure.crontab-user-not-touch-no-cron-allow"
log_success      "${INSTALL_WATCHER}" "configure.watchdogs-installed-in-cron-bin" "${CONFIG_BASE_DIRECTORY}"
