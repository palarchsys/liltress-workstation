#!/usr/bin/env bash
# =============================================================================
# File       : core/journal.sh
# Updated at : 2026-11-07
# Creator    : palarchsys
# =============================================================================

check_log_path_private() {
    local path="$1"
    local base
    base="$(basename "${path}")"
    case "${base}" in
        secrets.conf|human.tsv|*.env|*.key|id_ed25519*|htpasswd*|*.htpasswd)
            return 0
            ;;
    esac
    case "${path}" in
        */accounts|*/accounts/*)
            return 0
            ;;
    esac
    return 1
}

publish_repo_logs() {
    local path="${1:-}"
    local root="${INSTALL_DIRECTORY:-}"
    [[ -n "$path" && -e "$path" && -n "$root" ]] || return 0
    local abs_root abs_path
    abs_root="$(cd "$root" 2>/dev/null && pwd)" || return 0
    if [[ -d "$path" ]]; then
        abs_path="$(cd "$path" 2>/dev/null && pwd)" || return 0
    else
        abs_path="$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")" || return 0
    fi
    [[ "$abs_path" == "$abs_root" || "$abs_path" == "${abs_root}/"* ]] || return 0

    local og file
    og="$(stat -c '%u:%g' "$abs_root" 2>/dev/null || true)"

    if [[ -f "$path" ]]; then
        if check_log_path_private "$path"; then
            rm -f "$path"
            return 0
        fi
        chmod 644 "$path" 2>/dev/null || true
        if [[ -n "$og" && "$og" != "0:0" ]]; then
            chown "$og" "$path" 2>/dev/null || true
        fi
        return 0
    fi

    while IFS= read -r file; do
        if check_log_path_private "$file"; then
            rm -f "$file"
        fi
    done < <(find "$path" -type f -print 2>/dev/null)

    find "$path" -type d -empty -name accounts -exec rmdir {} + 2>/dev/null || true

    while IFS= read -r file; do
        [[ -e "$file" ]] || continue
        if [[ -d "$file" ]]; then
            chmod 755 "$file" 2>/dev/null || true
        else
            chmod 644 "$file" 2>/dev/null || true
        fi
        if [[ -n "$og" && "$og" != "0:0" ]]; then
            chown "$og" "$file" 2>/dev/null || true
        fi
    done < <(find "$path" -print 2>/dev/null)
}

publish_install_dir_logs() { publish_repo_logs "$@"; }

log_index_append() {
    local step="$1"
    local exit_code="$2"
    local log_path="$3"
    local line
    line="$(date -Iseconds)"$'\t'"${step}"$'\t'"${exit_code}"$'\t'"${log_path}"
    if [[ -n "${INSTALL_LOG_DIR:-}" ]]; then
        mkdir -p "${INSTALL_LOG_DIR}/steps"
        printf '%s\n' "${line}" >> "${INSTALL_LOG_DIR}/steps/INDEX.tsv"
    fi
}

# Prefer the release already resolved. Read os-release when the caller has not.
# Append the version number when that release name omits it.
get_distribution_label() {
    local os_pretty="${OS_PRETTY:-}"
    local os_version="${UBUNTU_BASE_VERSION:-${OS_VERSION_ID:-}}"
    local release_pretty=""
    local release_version=""
    local release_lines=()

    if [[ -z "${os_pretty}" || -z "${os_version}" ]]; then
        mapfile -t release_lines < <(
            # shellcheck disable=SC1091
            . /etc/os-release 2>/dev/null || true
            printf '%s\n%s\n' "${PRETTY_NAME:-}" "${VERSION_ID:-}"
        ) || true
        release_pretty="${release_lines[0]:-}"
        release_version="${release_lines[1]:-}"
        [[ -z "${os_pretty}" ]] && os_pretty="${release_pretty}"
        [[ -z "${os_version}" ]] && os_version="${release_version}"
    fi
    [[ -z "${os_pretty}" ]] && os_pretty="inconnue"
    if [[ -n "${os_version}" && "${os_pretty}" != *"${os_version}"* ]]; then
        os_pretty="${os_pretty} ${os_version}"
    fi
    printf '%s\n' "${os_pretty}"
}

init_install_log() {
    local root="${INSTALL_DIRECTORY:-.}"
    local stamp name kind old_umask os_label
    stamp="$(date '+%Y%m%d-%H%M%S')"
    kind="${SERVER_TYPE:-}"
    if [[ -z "${kind}" ]]; then
        if declare -F check_workstation >/dev/null 2>&1 && check_workstation; then
            kind="workstation"
        else
            kind="unknown"
        fi
    fi
    name="install-${stamp}-${kind}"

    INSTALL_LOG_DIR="${root}/log/${name}"
    LOG_SYS=""
    old_umask="$(umask)"
    umask 022
    mkdir -p "${INSTALL_LOG_DIR}/steps"
    INSTALL_LOG_FILE="${INSTALL_LOG_DIR}/install.log"
    : > "${INSTALL_LOG_FILE}"
    umask "${old_umask}"
    export INSTALL_LOG_DIR INSTALL_LOG_FILE LOG_SYS

    os_label="$(get_distribution_label)"
    printf '%s\n' "os          : ${os_label}" >> "${INSTALL_LOG_FILE}"

    {
        echo "$(get_text log.install-log "${PROJECT_NAME:-Liltress}")"
        echo "date        : $(date -Iseconds)"
        echo "hostname    : $(hostname 2>/dev/null || echo '?')"
        echo "os          : ${os_label}"
        echo "user        : ${CURRENT_USER:-}"
        echo "SERVER_TYPE : ${SERVER_TYPE:-}"
        echo "MODE_TEST   : ${MODE_TEST:-}"
        echo "MODE_DEV    : ${MODE_DEV:-}"
        echo "DIR         : ${root}"
        echo "log dir     : ${INSTALL_LOG_DIR}"
        echo "uname       : $(uname -a 2>/dev/null || true)"
    } | tee "${INSTALL_LOG_DIR}/meta.txt" >/dev/null

    exec > >(tee -a "${INSTALL_LOG_FILE}") 2>&1
    publish_repo_logs "${INSTALL_LOG_DIR}"
}

collect_common_snapshot() {
    local snap="$1"
    mkdir -p "${snap}"

    {
        hostnamectl 2>/dev/null || hostname
        echo "---"
        date -Iseconds
        echo "---"
        uptime
        echo "---"
        uname -a
        echo "---"
        echo "CURRENT_USER=${CURRENT_USER:-}"
        echo "SERVER_TYPE=${SERVER_TYPE:-}"
    } > "${snap}/host.txt" 2>&1 || true

    {
        echo "=== ip ==="
        ip -br a 2>/dev/null || ifconfig 2>/dev/null || true
        echo "=== df ==="
        df -h 2>/dev/null || true
        echo "=== units failed ==="
        systemctl --failed --no-pager 2>/dev/null || true
        echo "=== timers ==="
        systemctl list-timers --no-pager 2>/dev/null || true
        echo "=== kvm ==="
        ls -l /dev/kvm 2>/dev/null || true
        echo "=== virsh ==="
        virsh list --all 2>/dev/null || true
    } > "${snap}/system.txt" 2>&1 || true

    journalctl -b --no-pager -n 4000 > "${snap}/journalctl-boot.txt" 2>&1 || true
    dmesg -T 2>/dev/null | tail -n 500 > "${snap}/dmesg.txt" || true
    copy_installed_logs "${snap}" || true

    ufw status verbose > "${snap}/ufw-status.txt" 2>&1 || true
    sshd -t > "${snap}/sshd-t.txt" 2>&1 || true
    sshd -T > "${snap}/sshd-T.txt" 2>&1 || true
    aa-status > "${snap}/apparmor-status.txt" 2>&1 || true
}

collect_install_log() {
    [[ -n "${INSTALL_LOG_DIR:-}" && -d "${INSTALL_LOG_DIR}" ]] || return 0
    [[ "${LOGS_COLLECTED:-0}" == "1" ]] && return 0
    LOGS_COLLECTED=1
    export LOGS_COLLECTED

    local snap="${INSTALL_LOG_DIR}/snapshot"
    mkdir -p "$snap"
    log_info "${INSTALL_WATCHER:-BASH}" "install.log.info" "${snap}"
    collect_common_snapshot "${snap}"

    if declare -F collect_product_logs >/dev/null 2>&1; then
        collect_product_logs "${snap}" || true
    fi
    if declare -F collect_workstation_logs >/dev/null 2>&1; then
        collect_workstation_logs "${snap}" || true
    fi

    {
        echo "$(get_text log.g-collect-install-log "$(date -Iseconds)")"
        echo "dossier : ${INSTALL_LOG_DIR}"
        echo "os          : $(get_distribution_label)"
        echo "$(get_text log.see-install-log-errors-log-and-steps-index-tsv)"
        echo "$(get_text log.software-snapshot-software-and-snapshot-journal)"
    } > "${snap}/COLLECTED.txt"

    log_info "${INSTALL_WATCHER:-BASH}" "install.log.info.2"
    publish_repo_logs "${INSTALL_LOG_DIR}"
}

install_exit() {
    local code=$?
    if [[ "${code}" -ne 0 ]]; then
        collect_install_log || true
    fi
    publish_repo_logs "${INSTALL_LOG_DIR:-}" || true
}

ask() {
    local label="$1"
    local __var="$2"
    local width="${#label}"
    local value=""
    if (( width < 12 )); then
        width=12
    fi
    echo "" >&2
    printf '         \e[34m%*s\e[0m : ' "${width}" "${label}" >&2
    IFS= read -r value < /dev/tty || log_error "${INSTALL_WATCHER:-BASH}" "install.log.error.2"
    printf -v "${__var}" '%s' "${value}"
}

check_installer_directory() {
    local root="$1"
    local base="$2"
    [[ -n "${root}" && "${root}" == /* && -d "${root}" ]] || return 1
    [[ "${root}" != *[[:space:]]* && "${root}" != *$'\n'* ]] || return 1
    case "${root}" in
        /|/opt|/usr|/bin|/sbin|/lib|/lib64|/etc|/var|/home|/boot|/tmp|/root|/srv|/proc|/sys|/dev|/run)
            return 1
            ;;
    esac
    [[ "${root#/}" == */* ]] || return 1
    [[ -f "${root}/liltress" && -f "${root}/script/run.sh" ]] || return 1
    [[ -n "${base}" && "${base}" == /* && -d "${base}" ]] || return 1
    [[ "${base}" != *[[:space:]]* ]] || return 1

    case "${base}/" in
        "${root}/"*) return 1 ;;
    esac
    return 0
}

remove_installer_tree() {
    local root="" base="" mail="" conf="" tmp="" back="" rm_rc=0
    root="$(cd -- "${INSTALL_DIRECTORY:?}" && pwd -P)" || return 1
    base="$(cd -- "${CONFIG_BASE_DIRECTORY:?}" && pwd -P)" || return 1
    check_installer_directory "${root}" "${base}" || return 1
    if [[ -f "${root}/core/mail.sh" ]]; then
        mail="${root}/core/mail.sh"
    elif [[ -f "${root}/../share/core/mail.sh" ]]; then
        mail="${root}/../share/core/mail.sh"
    else
        return 2
    fi
    conf="${root}/config/global.conf"
    [[ -f "${conf}" ]] || return 2
    tmp="$(mktemp -d)" || return 2
    if ! install -m 644 -- "${conf}" "${tmp}/global.conf" \
        || ! install -m 644 -- "${mail}" "${tmp}/mail.sh"; then
        rm -rf -- "${tmp}"
        return 2
    fi
    [[ -f "${root}/core/log.sh" ]] && install -m 644 -- "${root}/core/log.sh" "${tmp}/log.sh"
    [[ -f "${root}/core/text.sh" ]] && install -m 644 -- "${root}/core/text.sh" "${tmp}/text.sh"
    [[ -f "${root}/core/display.sh" ]] && install -m 644 -- "${root}/core/display.sh" "${tmp}/display.sh"
    [[ -f "${root}/core/journal.sh" ]] && install -m 644 -- "${root}/core/journal.sh" "${tmp}/journal.sh"
    [[ -f "${root}/core/watchdog-load.sh" ]] && install -m 644 -- "${root}/core/watchdog-load.sh" "${tmp}/watchdog-load.sh"
    [[ -f "${root}/core/fs.sh" ]] && install -m 644 -- "${root}/core/fs.sh" "${tmp}/fs.sh"
    [[ -d "${root}/core/text" ]] && cp -a "${root}/core/text" "${tmp}/text"
    [[ -d "${root}/locale" ]] && cp -a "${root}/locale" "${tmp}/locale"
    [[ -f "${root}/config/chkrootkit/patterns.ignore" ]] \
        && install -m 644 -- "${root}/config/chkrootkit/patterns.ignore" "${tmp}/patterns.ignore"
    [[ -f "${root}/config/clamav/onaccess.conf" ]] \
        && install -m 644 -- "${root}/config/clamav/onaccess.conf" "${tmp}/onaccess.conf"
    back="$(pwd -P 2>/dev/null || true)"
    cd / || { rm -rf -- "${tmp}"; return 1; }
    rm -rf -- "${root}" || rm_rc=$?
    if ! install -d -m 755 -- "${base}/src" "${base}/src/core" "${base}/src/config" \
        || ! install -m 644 -- "${tmp}/global.conf" "${base}/src/config/global.conf" \
        || ! install -m 644 -- "${tmp}/mail.sh" "${base}/src/core/mail.sh"; then
        rm -rf -- "${tmp}"
        if [[ -n "${back}" && -d "${back}" ]]; then
            cd -- "${back}" || true
        fi
        return 4
    fi
    [[ -f "${tmp}/log.sh" ]] && install -m 644 -- "${tmp}/log.sh" "${base}/src/core/log.sh"
    [[ -f "${tmp}/text.sh" ]] && install -m 644 -- "${tmp}/text.sh" "${base}/src/core/text.sh"
    [[ -f "${tmp}/display.sh" ]] && install -m 644 -- "${tmp}/display.sh" "${base}/src/core/display.sh"
    [[ -f "${tmp}/journal.sh" ]] && install -m 644 -- "${tmp}/journal.sh" "${base}/src/core/journal.sh"
    [[ -f "${tmp}/watchdog-load.sh" ]] && install -m 644 -- "${tmp}/watchdog-load.sh" "${base}/src/core/watchdog-load.sh"
    [[ -f "${tmp}/fs.sh" ]] && install -m 644 -- "${tmp}/fs.sh" "${base}/src/core/fs.sh"
    if [[ -d "${tmp}/text" ]]; then
        install -d -m 755 -- "${base}/src/core/text"
        cp -a "${tmp}/text/." "${base}/src/core/text/"
    fi
    if [[ -d "${tmp}/locale" ]]; then
        install -d -m 755 -- "${base}/src/locale"
        cp -a "${tmp}/locale/." "${base}/src/locale/"
    fi
    if [[ -f "${tmp}/patterns.ignore" ]]; then
        install -d -m 755 -- "${base}/src/config/chkrootkit"
        install -m 644 -- "${tmp}/patterns.ignore" "${base}/src/config/chkrootkit/patterns.ignore"
    fi
    if [[ -f "${tmp}/onaccess.conf" ]]; then
        install -d -m 755 -- "${base}/src/config/clamav"
        install -m 644 -- "${tmp}/onaccess.conf" "${base}/src/config/clamav/onaccess.conf"
    fi
    rm -rf -- "${tmp}"
    if [[ -n "${back}" && -d "${back}" ]]; then
        cd -- "${back}" || true
    fi
    if [[ "${rm_rc}" -ne 0 || -e "${root}/liltress" || -e "${root}/config/secrets.conf" || -e "${root}/script/run.sh" ]]; then
        return 3
    fi
    [[ -f "${base}/src/config/global.conf" && -f "${base}/src/core/mail.sh" ]] || return 4
    [[ ! -e "${base}/src/config/secrets.conf" || "${root}" != "${base}/src" ]] || return 3
    return 0
}

offer_remove_installer() {
    local root=""
    root="$(cd -- "${INSTALL_DIRECTORY:?}" && pwd -P)" || {
        log_warn "${INSTALL_WATCHER:-BASH}" "install.log.warn.8"
        return 0
    }
    show_closing_command "$(get_text install.log.info.4)" "sudo rm -rf ${root}"
    return 0
}

collect_manual() {
    local root="${INSTALL_DIRECTORY:-.}"
    local stamp name old_umask
    stamp="$(date '+%Y%m%d-%H%M%S')"
    name="snapshot-${stamp}-$(hostname -s 2>/dev/null || hostname)"
    SERVER_TYPE="${SERVER_TYPE:-manual}"
    INSTALL_LOG_DIR="${root}/log/${name}"
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
    printf '%s\n' "$1" >> "${snap}/snapshot/truncated.txt"
}

copy_log_file() {
    local src="$1"
    local dest="$2"
    local max size
    [[ -f "${src}" ]] || return 0
    if check_log_path_private "${src}"; then
        return 0
    fi
    [[ -r "${src}" ]] || {
        log_note "illisible ${src}"
        return 0
    }
    max="$(get_log_copy_limit)"
    size="$(stat -c '%s' "${src}" 2>/dev/null || echo 0)"
    mkdir -p "$(dirname "${dest}")"
    case "${src}" in
        *.gz|*.xz|*.zst)
            if [[ "${size}" -gt "${max}" ]]; then
                log_note "$(get_text log.ignored-compressed-octets "${size}" "${src}")"
                return 0
            fi
            cp -f -- "${src}" "${dest}" 2>/dev/null || return 0
            ;;
        *)
            if [[ "${size}" -gt "${max}" ]]; then
                tail -c "${max}" "${src}" > "${dest}" 2>/dev/null || return 0
                log_note "$(get_text log.end-of-file-only-octets-kept "${size}" "${max}" "${src}")"
            else
                cp -f -- "${src}" "${dest}" 2>/dev/null || return 0
            fi
            ;;
    esac
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
        journalctl -u "${unit}" -b --no-pager -n 2000 > "${snap}/journal/${unit}.log" 2>&1 || true
        chmod 644 "${snap}/journal/${unit}.log" 2>/dev/null || true
    done
    return 0
}
