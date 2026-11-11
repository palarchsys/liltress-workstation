#!/usr/bin/env bash
# =============================================================================
# File       : core/log/install-log.sh
# Updated at : 2026-11-11
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
