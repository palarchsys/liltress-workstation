#!/usr/bin/env bash
# =============================================================================
# File       : service/clamav/configure.sh
# Updated at : 2026-11-07
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
# shellcheck disable=SC1091
source "$(locate_config_file clamav/onaccess.conf)"
require_root

add_onaccess_directory() {
    local path="$1"
    [[ -n "${path}" && "${path}" != "/" && -d "${path}" ]] || return 0
    grep -qxF "OnAccessIncludePath ${path}" "${clam_conf}" && return 0
    printf 'OnAccessIncludePath %s\n' "${path}" >> "${clam_conf}"
}

remove_onaccess_directory() {
    local path="$1"
    [[ -n "${path}" && -f "${clam_conf}" ]] || return 0
    sed -i "\|^OnAccessIncludePath ${path}\$|d" "${clam_conf}"
}

ensure_xdg_directory() {
    local key="$1"
    local fallback="$2"
    local path
    path="$(sudo -u "${CURRENT_USER}" -H xdg-user-dir "${key}" 2>/dev/null || true)"
    [[ -n "${path}" && -d "${path}" ]] || path="${CURRENT_HOME}/${fallback}"
    install -d -m 755 -o "${CURRENT_USER}" -g "${CURRENT_USER}" "${path}"
    printf '%s\n' "${path}"
}

log_info         "${INSTALL_WATCHER}" "configure.update-of-the-signatures-can-take-1-2-min"

run_optional     "${INSTALL_WATCHER}" "configure.clamav.error" systemctl stop clamav-freshclam
fresh_log="${INSTALL_LOG_DIR:-/var/log/liltress-workstation}/freshclam.log"
mkdir -p "$(dirname "${fresh_log}")"
if freshclam --quiet >"${fresh_log}" 2>&1; then
    log_success      "${INSTALL_WATCHER}" "configure.signatures-clamav-mises-up-to-date"
else
    log_warn         "${INSTALL_WATCHER}" "configure.clamav.warn"
fi
log_info         "${INSTALL_WATCHER}" "configure.activation-of-the-monitoring-clamav"
run_silent       "${INSTALL_WATCHER}" "configure.clamav.error" systemctl enable --now clamav-freshclam
run_silent       "${INSTALL_WATCHER}" "configure.clamav.error" systemctl enable --now clamav-daemon

get_current_user
install -d -m 755 "${CONFIG_BASE_DIRECTORY}/cron/bin"
install -m 755 \
    "${INSTALL_DIRECTORY}/service/cron/watchdogs/common.sh" \
    "${INSTALL_DIRECTORY}/service/cron/watchdogs/clamav-event.sh" \
    "${INSTALL_DIRECTORY}/service/cron/watchdogs/clamav-response.sh" \
    "${CONFIG_BASE_DIRECTORY}/cron/bin/"
rm -f "${CONFIG_BASE_DIRECTORY}/cron/clamav.conf"

download_dir="$(ensure_xdg_directory DOWNLOAD Downloads)"
desktop_dir="$(ensure_xdg_directory DESKTOP Desktop)"
documents_dir="$(ensure_xdg_directory DOCUMENTS Documents)"
music_dir="$(ensure_xdg_directory MUSIC Music)"
pictures_dir="$(ensure_xdg_directory PICTURES Pictures)"
videos_dir="$(ensure_xdg_directory VIDEOS Videos)"

event="${CONFIG_BASE_DIRECTORY}/cron/bin/clamav-event.sh"
clam_conf="/etc/clamav/clamd.conf"
if [[ -f "${clam_conf}" ]]; then
    if ! grep -q "${ONACCESS_MARKER}" "${clam_conf}" \
        && ! grep -q "High-Fortress User onaccess" "${clam_conf}"; then
        printf '\n# %s\n' "${ONACCESS_MARKER}" >> "${clam_conf}"
    fi
    add_onaccess_directory "${download_dir}"
    add_onaccess_directory "${desktop_dir}"
    add_onaccess_directory "${documents_dir}"
    add_onaccess_directory "${music_dir}"
    add_onaccess_directory "${pictures_dir}"
    add_onaccess_directory "${videos_dir}"
    add_onaccess_directory /tmp
    add_onaccess_directory /var/tmp
    add_onaccess_directory /opt
    if [[ "${ONACCESS_MOUNTS}" == "1" ]]; then
        add_onaccess_directory /media
        add_onaccess_directory /mnt
    else
        remove_onaccess_directory /media
        remove_onaccess_directory /mnt
    fi
    grep -qx "OnAccessExcludeUname ${ONACCESS_EXCLUDE_UNAME}" "${clam_conf}" \
        || printf 'OnAccessExcludeUname %s\n' "${ONACCESS_EXCLUDE_UNAME}" >> "${clam_conf}"
    grep -qx "OnAccessExcludeRootUID ${ONACCESS_EXCLUDE_ROOTUID}" "${clam_conf}" \
        || printf 'OnAccessExcludeRootUID %s\n' "${ONACCESS_EXCLUDE_ROOTUID}" >> "${clam_conf}"
    if grep -q '^OnAccessMaxFileSize ' "${clam_conf}"; then
        sed -i "s|^OnAccessMaxFileSize .*|OnAccessMaxFileSize ${ONACCESS_MAX_FILE_SIZE}|" "${clam_conf}"
    else
        printf 'OnAccessMaxFileSize %s\n' "${ONACCESS_MAX_FILE_SIZE}" >> "${clam_conf}"
    fi
    grep -qx "OnAccessPrevention ${ONACCESS_PREVENTION}" "${clam_conf}" \
        || printf 'OnAccessPrevention %s\n' "${ONACCESS_PREVENTION}" >> "${clam_conf}"
    grep -qx "OnAccessExtraScanning ${ONACCESS_EXTRA_SCANNING}" "${clam_conf}" \
        || printf 'OnAccessExtraScanning %s\n' "${ONACCESS_EXTRA_SCANNING}" >> "${clam_conf}"
    virus_line="VirusEvent sudo -n --preserve-env=${CLAMAV_VIRUS_EVENT_PRESERVE} ${event}"
    if grep -q '^VirusEvent ' "${clam_conf}"; then
        sed -i "s|^VirusEvent .*|${virus_line}|" "${clam_conf}"
    else
        printf '%s\n' "${virus_line}" >> "${clam_conf}"
    fi
    if ! grep -q '^TemporaryDirectory ' "${clam_conf}"; then
        printf 'TemporaryDirectory %s\n' "${CLAMAV_TEMPORARY_DIRECTORY}" >> "${clam_conf}"
    fi
fi

install -d -m 755 -o clamav -g clamav "${CLAMAV_TEMPORARY_DIRECTORY}"
tee /etc/sudoers.d/liltress-workstation-clamav > /dev/null << EOF
clamav ALL=(root) NOPASSWD: ${event}
EOF
chmod 440 /etc/sudoers.d/liltress-workstation-clamav
if ! visudo -cf /etc/sudoers.d/liltress-workstation-clamav >/dev/null; then
    rm -f /etc/sudoers.d/liltress-workstation-clamav
    log_error        "${INSTALL_WATCHER}" "configure.sudoers-clamav-invalid"
fi

if id clamav >/dev/null 2>&1; then
    install -d -m 750 -o clamav -g clamav "${CLAMAV_QUARANTINE}"
else
    install -d -m 750 "${CLAMAV_QUARANTINE}"
fi

run_silent       "${INSTALL_WATCHER}" "configure.clamav.error" systemctl daemon-reload
run_optional     "${INSTALL_WATCHER}" "configure.clamav.error" systemctl unmask clamav-clamonacc.service clamonacc.service
clam_unit="clamav-clamonacc.service"
if ! systemctl cat "${clam_unit}" >/dev/null 2>&1; then
    clam_unit="clamonacc.service"
fi
if ! systemctl cat "${clam_unit}" >/dev/null 2>&1; then
    log_error        "${INSTALL_WATCHER}" "configure.unit-clamonacc-not-found-the-monitoring-continue"
fi
install -d -m 755 "/etc/systemd/system/${clam_unit}.d"
tee "/etc/systemd/system/${clam_unit}.d/hfu.conf" > /dev/null << EOF
[Service]
ExecStart=
ExecStart=${CLAMONACC_BIN} -F --log=${CLAMONACC_LOG} --move=${CLAMAV_QUARANTINE}
Restart=${CLAMONACC_RESTART}
RestartSec=${CLAMONACC_RESTART_SEC}
EOF
run_silent       "${INSTALL_WATCHER}" "configure.clamav.error" systemctl daemon-reload

export BASE="${CONFIG_BASE_DIRECTORY}"
export SCAN_SKIP_HOME="${CURRENT_HOME}"
# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/service/cron/watchdogs/scan-skip-lib.sh"
ensure_scan_skip_file "${CURRENT_HOME}"
bash "${INSTALL_DIRECTORY}/service/cron/watchdogs/apply-scan-skip.sh"
run_silent       "${INSTALL_WATCHER}" "configure.clamav.error" systemctl enable --now "${clam_unit}"
run_silent       "${INSTALL_WATCHER}" "configure.clamav.error" systemctl restart clamav-daemon
run_silent       "${INSTALL_WATCHER}" "configure.clamav.error" systemctl restart "${clam_unit}"

sleep 3
clam_log="${INSTALL_LOG_DIR:-/var/log/liltress-workstation}/clamonacc.log"
mkdir -p "$(dirname -- "${clam_log}")"
journalctl -u "${clam_unit}" -b --no-pager > "${clam_log}" 2>&1 || true
if ! systemctl is-active --quiet "${clam_unit}"; then
    log_error        "${INSTALL_WATCHER}" "configure.clamonacc-stays-not-active-detail-clamonacc-log" "${INSTALL_LOG_DIR:-/var/log/liltress-workstation}"
fi
if grep -q "can't exclude" "${clam_log}"; then
    log_error        "${INSTALL_WATCHER}" "configure.clamonacc-exclude-stopped-the-watches" "${INSTALL_LOG_DIR:-/var/log/liltress-workstation}"
fi
zone_label="les dossiers utilisateur, /tmp, /var/tmp et /opt"
if [[ "${ONACCESS_MOUNTS}" == "1" ]]; then
    zone_label="${zone_label}, /media et /mnt"
fi
log_success      "${INSTALL_WATCHER}" "configure.clamav-launched-in-monitoring-continues-on" "${zone_label}"
