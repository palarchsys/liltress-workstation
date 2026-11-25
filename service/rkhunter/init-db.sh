#!/usr/bin/env bash
# =============================================================================
# File       : service/rkhunter/init-db.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Build the rootkit-hunter baseline when it is missing or a rebuild is requested.
# Note       : Update codes 0 and 2 are accepted.
# -----------------------------------------------------------------------------


rkhunter_init_db_01_run_01_record() {
    INSTALL_WATCHER="${1:-BASH}"
    INSTALL_DIRECTORY="${2:-}"
    export INSTALL_WATCHER INSTALL_DIRECTORY
    source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
    source "${INSTALL_DIRECTORY}/config/global.conf"
    require_root
    if [[ "${REBUILD_BASE:-0}" != "1" && -f /var/lib/rkhunter/db/rkhunter.dat ]]; then
        log_info "${INSTALL_WATCHER}" "log.base-already-present"
        exit 0
    fi
    log_info "${INSTALL_WATCHER}" "log.record-of-the-baseline-rkhunter"
    rk_out=""
    rk_rc=0
    rk_out=$(rkhunter --update --nocolors 2>&1) || rk_rc=$?
    case "${rk_rc}" in
        0 | 2) ;;
        *) log_warn "${INSTALL_WATCHER}" "log.rkhunter-update-rc-continued" "${rk_rc}" "${rk_out}" ;;
    esac
}

rkhunter_init_db_01_run_02_record() {
    if [[ ("${rk_rc}" -eq 0 || "${rk_rc}" -eq 2) && -x "${CONFIG_BASE_DIRECTORY}/service/cron/watchdogs/record-mirrors.sh" ]]; then
        BASE="${CONFIG_BASE_DIRECTORY}" bash "${CONFIG_BASE_DIRECTORY}/service/cron/watchdogs/record-mirrors.sh" save || true
    fi
    run_silent "${INSTALL_WATCHER}" "install.rkhunter.error" rkhunter --propupd
    rk_tmp="/var/lib/rkhunter/tmp"
    if [[ -d "${rk_tmp}" ]]; then
        cp -f -p /etc/passwd "${rk_tmp}/passwd"
        cp -f -p /etc/group "${rk_tmp}/group"
    fi
    log_success "${INSTALL_WATCHER}" "log.baseline-rkhunter-saved"
}

rkhunter_init_db_01_run_03_run() {
    rkhunter_init_db_01_run_01_record "$@"
    rkhunter_init_db_01_run_02_record "$@"
}

rkhunter_init_db_01_run_03_run "$@"
