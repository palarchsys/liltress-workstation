#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/configure.sh
# Updated at : 2026-11-06
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

# shellcheck disable=SC2155
readonly DIR_SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${INSTALL_DIRECTORY}/core/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root
get_current_user


cpu_quota="$(
    WATCHDOG_CPU_LIMIT="${WATCHDOG_CPU_LIMIT:-50}" \
        bash -c 'source "$1" && get_cpu_quota_percent' _ "${INSTALL_DIRECTORY}/core/watchdog.sh"
)" || log_error        "${INSTALL_WATCHER}" "configure.quota-cpu-not-found"
[[ "${cpu_quota}" =~ ^[0-9]+$ ]] || log_error        "${INSTALL_WATCHER}" "configure.quota-cpu-invalid" "${cpu_quota:-vide}"
# shellcheck disable=SC1091
source "$(locate_config_file cron/timers.conf)"

log_info         "${INSTALL_WATCHER}" "configure.installation-of-the-watchdogs-chain-to-the-start" "${WATCHDOG_CPU_LIMIT}"
ensure_directory "${CONFIG_BASE_DIRECTORY}/cron/bin" 755
ensure_directory "${CONFIG_BASE_DIRECTORY}/cron/cron_logs" 750
ensure_directory "${CONFIG_BASE_DIRECTORY}/cron/security_logs" 750
ensure_directory "${CONFIG_BASE_DIRECTORY}/cron/alerts" 750

cp -a "${DIR_SCRIPT_PATH}/watchdogs/." "${CONFIG_BASE_DIRECTORY}/cron/bin/"
chmod 750 "${CONFIG_BASE_DIRECTORY}/cron/bin/"*.sh
source_core mail.sh
install_mail_templates "${CONFIG_BASE_DIRECTORY}/cron/bin"
mail_src="$(readlink -f "${INSTALL_DIRECTORY}/core/mail.sh")"
[[ -f "${mail_src}" ]] || log_error        "${INSTALL_WATCHER}" "configure.core-mail-sh-not-found-core-mail-sh" "${INSTALL_DIRECTORY}"
cp -f "${mail_src}" "${CONFIG_BASE_DIRECTORY}/cron/bin/mail.sh"
chmod 750 "${CONFIG_BASE_DIRECTORY}/cron/bin/mail.sh"
watch_src="$(readlink -f "${INSTALL_DIRECTORY}/core/watchdog.sh")"
[[ -f "${watch_src}" ]] || log_error        "${INSTALL_WATCHER}" "configure.core-watchdog-sh-not-found" "${INSTALL_DIRECTORY}/core/watchdog.sh"
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

copy_runtime_dir() {
    local src="$1" dest="$2" src_real="" dest_real=""
    [[ -d "${src}" ]] || return 0
    src_real="$(readlink -f "${src}")"
    if [[ -d "${dest}" ]]; then
        dest_real="$(readlink -f "${dest}" 2>/dev/null || true)"
        [[ "${src_real}" == "${dest_real}" ]] && return 0
    fi
    install -d -m 755 "${dest}"
    cp -a "${src_real}/." "${dest}/"
}

copy_runtime_file "${INSTALL_DIRECTORY}/core/log.sh" \
    "${CONFIG_BASE_DIRECTORY}/cron/bin/log.sh" 644
copy_runtime_file "${INSTALL_DIRECTORY}/core/log.sh" \
    "${CONFIG_BASE_DIRECTORY}/bin/log.sh" 644
copy_runtime_file "${INSTALL_DIRECTORY}/core/log.sh" \
    "${CONFIG_BASE_DIRECTORY}/src/core/log.sh" 644
copy_runtime_file "${INSTALL_DIRECTORY}/core/watchdog-load.sh" \
    "${CONFIG_BASE_DIRECTORY}/src/core/watchdog-load.sh" 644
copy_runtime_file "${INSTALL_DIRECTORY}/core/fs.sh" \
    "${CONFIG_BASE_DIRECTORY}/src/core/fs.sh" 644
copy_runtime_dir "${INSTALL_DIRECTORY}/core/text" \
    "${CONFIG_BASE_DIRECTORY}/core/text"
copy_runtime_dir "${INSTALL_DIRECTORY}/locale" \
    "${CONFIG_BASE_DIRECTORY}/locale"
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
RCLONE_ALERTS="${RCLONE_ALERTS:-0}"
RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive}"
RCLONE_PATH="${RCLONE_PATH:-liltress-alerts}"
EOF
umask 022
chmod 600 "${CONFIG_BASE_DIRECTORY}/cron/mail.conf"
chown -R root:root "${CONFIG_BASE_DIRECTORY}/cron"
if [[ -f "${CONFIG_BASE_DIRECTORY}/cron/rclone.conf" ]]; then
    chown root:root "${CONFIG_BASE_DIRECTORY}/cron/rclone.conf"
    chmod 600 "${CONFIG_BASE_DIRECTORY}/cron/rclone.conf"
fi

export W_PROJECT_SLUG CONFIG_BASE_DIRECTORY

sed "s|\${CONFIG_BASE_DIRECTORY}|${CONFIG_BASE_DIRECTORY}|g" "$(locate_config_file cron/schedule.cron)" \
    > "/etc/cron.d/${W_PROJECT_SLUG}"
chown root:root "/etc/cron.d/${W_PROJECT_SLUG}"
chmod 600 "/etc/cron.d/${W_PROJECT_SLUG}"

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
        -e "s|\\\${W_BOOT_ON_BOOT_SEC}|${W_BOOT_ON_BOOT_SEC}|g" \
        -e "s|\\\${W_BOOT_ACCURACY}|${W_BOOT_ACCURACY}|g" \
        -e "s|\\\${W_TIMER_PERSISTENT}|${W_TIMER_PERSISTENT}|g" \
        -e "s|\\\${W_IDLE_EVERY}|${W_IDLE_EVERY}|g" \
        -e "s|\\\${W_IDLE_ACCURACY}|${W_IDLE_ACCURACY}|g" \
        -e "s|\\\${W_REBOOT_EVERY}|${W_REBOOT_EVERY}|g" \
        -e "s|\\\${W_REBOOT_ACCURACY}|${W_REBOOT_ACCURACY}|g" \
        -e "s|\\\${W_PERIODIC_EVERY}|${W_PERIODIC_EVERY}|g" \
        -e "s|\\\${W_PERIODIC_ON_BOOT_SEC}|${W_PERIODIC_ON_BOOT_SEC}|g" \
        -e "s|\\\${W_PERIODIC_ACCURACY}|${W_PERIODIC_ACCURACY}|g" \
        -e "s|\\\${W_HOURLY_EVERY}|${W_HOURLY_EVERY}|g" \
        -e "s|\\\${W_HOURLY_ON_BOOT_SEC}|${W_HOURLY_ON_BOOT_SEC}|g" \
        -e "s|\\\${W_HOURLY_ACCURACY}|${W_HOURLY_ACCURACY}|g" \
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
run_silent       "${INSTALL_WATCHER}" "configure.cron.error.9" systemctl enable w-boot-chain.timer
run_silent       "${INSTALL_WATCHER}" "configure.cron.error.10" systemctl enable w-idle-scan.timer
run_silent       "${INSTALL_WATCHER}" "configure.cron.error.11" systemctl enable w-reboot-notice.timer
run_silent       "${INSTALL_WATCHER}" "configure.cron.error.12" systemctl enable w-periodic-scan.timer
run_silent       "${INSTALL_WATCHER}" "configure.cron.error.13" systemctl enable w-hourly-scan.timer
log_success      "${INSTALL_WATCHER}" "configure.chain-of-start-hourly-password-and-scan-all-the-2" "${WATCHDOG_CPU_LIMIT}"

export W_BASE="${CONFIG_BASE_DIRECTORY}"
export W_SCAN_SKIP_HOME="${CURRENT_HOME}"
# shellcheck disable=SC1091
source "${DIR_SCRIPT_PATH}/watchdogs/scan-skip-lib.sh"
ensure_scan_skip_file "${CURRENT_HOME}"
if [[ ! -d /var/jeux ]]; then
    install -d -m 750 -o "${CURRENT_USER}" -g "${CURRENT_USER}" /var/jeux
fi
install -d -m 755 "${CONFIG_BASE_DIRECTORY}/bin"
install -m 755 "${DIR_SCRIPT_PATH}/scan-skip.sh" "${CONFIG_BASE_DIRECTORY}/bin/scan-skip.sh"
install -m 755 "${DIR_SCRIPT_PATH}/boot-check.sh" "${CONFIG_BASE_DIRECTORY}/bin/boot-check.sh"
install -m 755 "$(readlink -f "${INSTALL_DIRECTORY}/core/quarantine-restore.sh")" \
    "${CONFIG_BASE_DIRECTORY}/bin/quarantine-restore.sh"
install -m 755 "$(readlink -f "${INSTALL_DIRECTORY}/core/mail-test.sh")" \
    "${CONFIG_BASE_DIRECTORY}/bin/mail-test.sh"
bash "${CONFIG_BASE_DIRECTORY}/cron/bin/apply-scan-skip.sh"

install -d -m 755 "${CONFIG_BASE_DIRECTORY}/config/integrity"
install -m 644 \
    "$(locate_config_file integrity/paths.list)" \
    "${CONFIG_BASE_DIRECTORY}/config/integrity/paths.list"
install -m 644 \
    "${INSTALL_DIRECTORY}/config/global.conf" \
    "${CONFIG_BASE_DIRECTORY}/config/global.conf"
export W_BASE="${CONFIG_BASE_DIRECTORY}"
run_silent       "${INSTALL_WATCHER}" "configure.cron.error.14" bash "${CONFIG_BASE_DIRECTORY}/cron/bin/integrity.sh"

log_info         "${INSTALL_WATCHER}" "configure.crontab-user-not-touch-no-cron-allow"
log_success      "${INSTALL_WATCHER}" "configure.watchdogs-installed-in-cron-bin" "${CONFIG_BASE_DIRECTORY}"
