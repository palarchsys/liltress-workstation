#!/usr/bin/env bash
# =============================================================================
# File       : core/log/install-log.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Name the install journal and the mode of its files.
# -----------------------------------------------------------------------------


check_log_path_private() {
    local path="$1"
    local base
    base="$(basename "${path}")"
    case "${base}" in
        secrets.conf | human.tsv | *.env | *.key | id_ed25519* | htpasswd* | *.htpasswd)
            return 0
            ;;
    esac
    case "${path}" in
        */accounts | */accounts/*)
            return 0
            ;;
    esac
    return 1
}

# The caller owns abs_root and abs_path. A path outside the install tree stops the call.
locate_repo_log() {
    local path="$1"
    local root="$2"
    abs_root="$(cd "${root}" 2>/dev/null && pwd)" || return 1
    if [[ -d "${path}" ]]; then
        abs_path="$(cd "${path}" 2>/dev/null && pwd)" || return 1
    else
        abs_path="$(cd "$(dirname "${path}")" 2>/dev/null && pwd)/$(basename "${path}")" || return 1
    fi
    [[ "${abs_path}" == "${abs_root}" || "${abs_path}" == "${abs_root}/"* ]] || return 1
    return 0
}

# The journal directories stay at mode 750.
set_install_log_modes() {
    if [[ -d "${abs_root}/log" ]]; then
        chmod 750 "${abs_root}/log" 2>/dev/null || true
    fi
    if [[ -d "${abs_root}/log/install" ]]; then
        chmod 750 "${abs_root}/log/install" 2>/dev/null || true
    fi
}

# Root keeps the file when the tree owner is root.
set_repo_log_owner() {
    local file="$1"
    local owner="$2"
    if [[ -n "${owner}" && "${owner}" != "0:0" ]]; then
        chown "${owner}" "${file}" 2>/dev/null || true
    fi
}

# A private file is removed. Any other file stays mode 640.
publish_log_file() {
    local path="$1"
    local owner="$2"
    if check_log_path_private "${path}"; then
        rm -f "${path}"
        return 0
    fi
    chmod 640 "${path}" 2>/dev/null || true
    set_repo_log_owner "${path}" "${owner}"
}

# Private names leave the tree, and an empty accounts directory leaves with them.
remove_private_log_files() {
    local path="$1"
    local file=""
    while IFS= read -r file; do
        if check_log_path_private "${file}"; then
            rm -f "${file}"
        fi
    done < <(find "${path}" -type f -print 2>/dev/null)
    find "${path}" -type d -empty -name accounts -exec rmdir {} + 2>/dev/null || true
}

# A directory is mode 750 and a file is mode 640.
apply_repo_log_modes() {
    local path="$1"
    local owner="$2"
    local file=""
    while IFS= read -r file; do
        [[ -e "${file}" ]] || continue
        if [[ -d "${file}" ]]; then
            chmod 750 "${file}" 2>/dev/null || true
        else
            chmod 640 "${file}" 2>/dev/null || true
        fi
        set_repo_log_owner "${file}" "${owner}"
    done < <(find "${path}" -print 2>/dev/null)
}

publish_repo_logs() {
    local path="${1:-}"
    local root="${INSTALL_DIRECTORY:-}"
    local abs_root="" abs_path="" og=""
    [[ -n "${path}" && -e "${path}" && -n "${root}" ]] || return 0
    locate_repo_log "${path}" "${root}" || return 0
    og="$(stat -c '%u:%g' "${abs_root}" 2>/dev/null || true)"
    set_install_log_modes
    if [[ -f "${path}" ]]; then
        publish_log_file "${path}" "${og}"
        return 0
    fi
    remove_private_log_files "${path}"
    apply_repo_log_modes "${path}" "${og}"
}

publish_install_directory_logs() { publish_repo_logs "$@"; }

log_index_append() {
    local step="$1"
    local exit_code="$2"
    local log_path="$3"
    local line
    line="$(date -Iseconds)"$'\t'"${step}"$'\t'"${exit_code}"$'\t'"${log_path}"
    if [[ -n "${INSTALL_LOG_DIR:-}" ]]; then
        mkdir -p "${INSTALL_LOG_DIR}/steps"
        printf '%s\n' "${line}" >>"${INSTALL_LOG_DIR}/steps/INDEX.tsv"
    fi
}

# The release file fills a missing pretty name or a missing version.
read_os_release_pair() {
    local pretty="$1"
    local version="$2"
    local release_lines=()
    mapfile -t release_lines < <(
        # shellcheck disable=SC1091
        . /etc/os-release 2>/dev/null || true
        printf '%s\n%s\n' "${PRETTY_NAME:-}" "${VERSION_ID:-}"
    ) || true
    if [[ -z "${pretty}" ]]; then
        pretty="${release_lines[0]:-}"
    fi
    if [[ -z "${version}" ]]; then
        version="${release_lines[1]:-}"
    fi
    printf '%s\n%s\n' "${pretty}" "${version}"
}

# An empty pretty name becomes the fixed word. A known version is joined once.
finish_distribution_label() {
    local pretty="$1"
    local version="$2"
    if [[ -z "${pretty}" ]]; then
        pretty="inconnue"
    fi
    if [[ -n "${version}" && "${pretty}" != *"${version}"* ]]; then
        pretty="${pretty} ${version}"
    fi
    printf '%s\n' "${pretty}"
}

# Prefer the release already resolved. Read os-release when the caller has not.
get_distribution_label() {
    local os_pretty="${OS_PRETTY:-}"
    local os_version="${UBUNTU_BASE_VERSION:-${OS_VERSION_ID:-}}"
    local release_lines=()
    if [[ -z "${os_pretty}" || -z "${os_version}" ]]; then
        mapfile -t release_lines < <(read_os_release_pair "${os_pretty}" "${os_version}")
        os_pretty="${release_lines[0]:-}"
        os_version="${release_lines[1]:-}"
    fi
    finish_distribution_label "${os_pretty}" "${os_version}"
}

read_conf_value() {
    local root="$1"
    local key="$2"
    awk -F= -v key="${key}" '$1 == key {
        gsub(/["\047]/, "", $2)
        gsub(/[[:space:]]/, "", $2)
        print $2
        exit
    }' "${root}/config/global.conf"
}

check_workstation_slug() {
    [[ "${1:-}" == "liltress-workstation" || "${PROJECT_SLUG:-}" == "liltress-workstation" ]]
}

read_root_kind() {
    local root="$1"
    if [[ -n "${root}" && "$(basename -- "${root}")" == "workstation" ]]; then
        printf '%s\n' workstation
        return 0
    fi
    if [[ -n "${root}" && "$(basename -- "${root}")" == "server" ]]; then
        printf '%s\n' server
        return 0
    fi
    return 1
}

get_tree_kind() {
    local root="$1"
    local slug="$2"
    local kind=""
    if check_workstation_slug "${slug}"; then
        kind="workstation"
    elif declare -F check_workstation >/dev/null 2>&1 && check_workstation; then
        kind="workstation"
    elif kind="$(read_root_kind "${root}")"; then
        :
    else
        kind="unknown"
    fi
    printf '%s\n' "${kind}"
}

log_product_kind() {
    local root="${1:-}"
    local kind="${SERVER_TYPE:-}"
    local slug=""
    if [[ -z "${kind}" && -n "${root}" && -f "${root}/config/global.conf" ]]; then
        kind=$(read_conf_value "${root}" SERVER_TYPE)
        slug=$(read_conf_value "${root}" PROJECT_SLUG)
    fi
    if [[ "${kind}" == "WORKSTATION" ]]; then
        kind=""
    fi
    if [[ -z "${kind}" ]]; then
        kind=$(get_tree_kind "${root}" "${slug}")
    fi
    printf '%s\n' "${kind}"
}

log_run_name() {
    local role="$1"
    local root="${2:-}"
    local stamp
    stamp="$(date '+%Y%m%d-%H%M%S')"
    printf '%s-%s-%s\n' "${role}" "${stamp}" "$(log_product_kind "${root}")"
}

init_install_log() {
    local root="${INSTALL_DIRECTORY:-.}"
    local name old_umask os_label
    name="$(log_run_name install "${root}")"

    INSTALL_LOG_DIR="${root}/log/install/${name}"
    LOG_SYS=""
    old_umask="$(umask)"
    umask 022
    mkdir -p "${INSTALL_LOG_DIR}/steps"
    INSTALL_LOG_FILE="${INSTALL_LOG_DIR}/install.log"
    : >"${INSTALL_LOG_FILE}"
    umask "${old_umask}"
    export INSTALL_LOG_DIR INSTALL_LOG_FILE LOG_SYS

    os_label="$(get_distribution_label)"
    printf '%s\n' "os          : ${os_label}" >>"${INSTALL_LOG_FILE}"

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
        echo "log directory     : ${INSTALL_LOG_DIR}"
        echo "uname       : $(uname -a 2>/dev/null || true)"
    } | tee "${INSTALL_LOG_DIR}/meta.txt" >/dev/null

    exec > >(tee -a "${INSTALL_LOG_FILE}") 2>&1
    publish_repo_logs "${INSTALL_LOG_DIR}"
}

write_host_snapshot() {
    local snap="$1"
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
    } >"${snap}/host.txt" 2>&1 || true
}

write_system_snapshot() {
    local snap="$1"
    {
        echo "=== ip ==="
        ip -br a 2>/dev/null || ifconfig 2>/dev/null || true
        echo "=== df ==="
        df -h 2>/dev/null
        echo "=== units failed ==="
        systemctl --failed --no-pager 2>/dev/null
        echo "=== timers ==="
        systemctl list-timers --no-pager 2>/dev/null
        echo "=== kvm ==="
        ls -l /dev/kvm 2>/dev/null
        echo "=== virsh ==="
        virsh list --all 2>/dev/null
    } >"${snap}/system.txt" 2>&1 || true
}

write_service_snapshot() {
    local snap="$1"
    ufw status verbose >"${snap}/ufw-status.txt" 2>&1 || true
    sshd -t >"${snap}/sshd-t.txt" 2>&1 || true
    sshd -T >"${snap}/sshd-T.txt" 2>&1 || true
    aa-status >"${snap}/apparmor-status.txt" 2>&1 || true
}

collect_common_snapshot() {
    local snap="$1"
    mkdir -p "${snap}"
    write_host_snapshot "${snap}"
    write_system_snapshot "${snap}"
    journalctl -b --no-pager -n 4000 >"${snap}/journalctl-boot.txt" 2>&1 || true
    dmesg -T 2>/dev/null | tail -n 500 >"${snap}/dmesg.txt" || true
    copy_installed_logs "${snap}" || true
    write_service_snapshot "${snap}"
}

collect_known_logs() {
    local snap="$1"
    if declare -F collect_product_logs >/dev/null 2>&1; then
        collect_product_logs "${snap}" || true
    fi
    if declare -F collect_workstation_logs >/dev/null 2>&1; then
        collect_workstation_logs "${snap}" || true
    fi
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
    collect_known_logs "${snap}"

    {
        echo "$(get_text log.g-collect-install-log "$(date -Iseconds)")"
        echo "dossier : ${INSTALL_LOG_DIR}"
        echo "os          : $(get_distribution_label)"
        echo "$(get_text log.see-install-log-errors-log-and-steps-index-tsv)"
        echo "$(get_text log.software-snapshot-software-and-snapshot-journal)"
    } >"${snap}/COLLECTED.txt"

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
