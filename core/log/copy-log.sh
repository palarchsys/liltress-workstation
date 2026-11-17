#!/usr/bin/env bash
# =============================================================================
# File       : core/log/copy-log.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Copy install journals and keep only the tail of a long file.
# Note       : A private path is left in place.
# -----------------------------------------------------------------------------


collect_manual() {
    local root="${INSTALL_DIRECTORY:-.}"
    local name old_umask
    name="$(log_run_name snapshot "${root}")"
    SERVER_TYPE="${SERVER_TYPE:-manual}"
    INSTALL_LOG_DIR="${root}/log/install/${name}"
    LOG_SYS=""
    old_umask="$(umask)"
    umask 022
    mkdir -p "${INSTALL_LOG_DIR}/snapshot"
    umask "${old_umask}"
    export INSTALL_LOG_DIR LOG_SYS SERVER_TYPE
    unset LOGS_COLLECTED
    collect_install_log
    log_info "${INSTALL_WATCHER:-BASH}" "install.log.info.9" "${INSTALL_LOG_DIR}"
}

get_log_copy_limit() {
    printf '%s\n' 8388608
}

log_note() {
    local snap="${INSTALL_LOG_DIR:-}"
    [[ -n "${snap}" ]] || return 0
    mkdir -p "${snap}/snapshot"
    printf '%s\n' "$1" >>"${snap}/snapshot/truncated.txt"
}

# The caller owns copy_stopped. A stop leaves the mode unchanged.
copy_compressed_log() {
    local src="$1"
    local dest="$2"
    local size="$3"
    local max="$4"
    if [[ "${size}" -gt "${max}" ]]; then
        log_note "$(get_text log.ignored-compressed-octets "${size}" "${src}")"
        copy_stopped=1
        return 0
    fi
    cp -f -- "${src}" "${dest}" 2>/dev/null || copy_stopped=1
    return 0
}

# The caller owns copy_stopped. A long plain file keeps only its final bytes.
copy_plain_log() {
    local src="$1"
    local dest="$2"
    local size="$3"
    local max="$4"
    if [[ "${size}" -gt "${max}" ]]; then
        tail -c "${max}" "${src}" >"${dest}" 2>/dev/null || copy_stopped=1
        if [[ "${copy_stopped}" -eq 0 ]]; then
            log_note "$(get_text log.end-of-file-only-octets-kept "${size}" "${max}" "${src}")"
        fi
        return 0
    fi
    cp -f -- "${src}" "${dest}" 2>/dev/null || copy_stopped=1
    return 0
}

copy_log_file() {
    local src="$1"
    local dest="$2"
    local max="" size="" copy_stopped=0
    [[ -f "${src}" ]] || return 0
    if check_log_path_private "${src}"; then
        return 0
    fi
    if [[ ! -r "${src}" ]]; then
        log_note "illisible ${src}"
        return 0
    fi
    max="$(get_log_copy_limit)"
    size="$(stat -c '%s' "${src}" 2>/dev/null || echo 0)"
    mkdir -p "$(dirname "${dest}")"
    case "${src}" in
        *.gz | *.xz | *.zst)
            copy_compressed_log "${src}" "${dest}" "${size}" "${max}"
            ;;
        *)
            copy_plain_log "${src}" "${dest}" "${size}" "${max}"
            ;;
    esac
    [[ "${copy_stopped}" -eq 0 ]] || return 0
    chmod 644 "${dest}" 2>/dev/null || true
}

copy_log_tree() {
    local src="$1"
    local dest_root="$2"
    local file dest
    [[ -e "${src}" ]] || return 0
    if [[ -f "${src}" ]]; then
        copy_log_file "${src}" "${dest_root}/${src#/}"
        return 0
    fi
    [[ -d "${src}" ]] || return 0
    while IFS= read -r -d '' file; do
        dest="${dest_root}/${file#/}"
        copy_log_file "${file}" "${dest}"
    done < <(find "${src}" -type f -print0 2>/dev/null)
    return 0
}

copy_installed_logs() {
    local snap="$1"
    local dest="${snap}/software"
    local src
    local -a paths=(
        /var/log/syslog
        /var/log/auth.log
        /var/log/kern.log
        /var/log/nginx
        /var/log/fail2ban.log
        /var/log/ufw.log
        /var/log/clamav
        /var/log/aide
        /var/lib/aide/aide.log
        /var/log/rkhunter.log
        /var/log/audit
        /var/log/crowdsec
        /var/log/mail.log
        /var/log/mail.err
        /var/log/redis
        /var/log/unattended-upgrades
        /var/log/letsencrypt
        /var/log/apt/term.log
        /var/log/apt/history.log
        /var/log/dpkg.log
    )
    for src in "${paths[@]}"; do
        copy_log_tree "${src}" "${dest}"
    done
    if [[ -n "${CONFIG_BASE_DIRECTORY:-}" ]]; then
        copy_log_tree "${CONFIG_BASE_DIRECTORY}/cron/cron_logs" "${dest}"
        copy_log_tree "${CONFIG_BASE_DIRECTORY}/cron/security_logs" "${dest}"
        copy_log_tree "${CONFIG_BASE_DIRECTORY}/cron/alerts" "${dest}"
    fi
    return 0
}

copy_unit_journals() {
    local snap="$1"
    shift
    local unit
    mkdir -p "${snap}/journal"
    for unit in "$@"; do
        systemctl cat "${unit}" >/dev/null 2>&1 || continue
        journalctl -u "${unit}" -b --no-pager -n 2000 >"${snap}/journal/${unit}.log" 2>&1 || true
        chmod 644 "${snap}/journal/${unit}.log" 2>/dev/null || true
    done
    return 0
}
