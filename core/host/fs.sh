#!/usr/bin/env bash
# =============================================================================
# File       : core/host/fs.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Create directories, keep one backup, and set modes on the installed tree.
# -----------------------------------------------------------------------------


# The caller owns roots.
add_config_roots() {
    if [[ -n "${INSTALL_DIRECTORY:-}" ]]; then
        roots+=("${INSTALL_DIRECTORY}")
    fi
    if [[ -n "${PRODUCT_ROOT:-}" ]]; then
        roots+=("${PRODUCT_ROOT}")
    fi
    if [[ -n "${CONFIG_BASE_DIRECTORY:-}" ]]; then
        roots+=("${CONFIG_BASE_DIRECTORY}")
    fi
    if [[ -n "${BASE:-}" ]]; then
        roots+=("${BASE}")
    fi
}

# The caller owns roots. The first parent that holds the shared tree is enough.
add_share_config_root() {
    local probe="" shared_parent=""
    for probe in "${INSTALL_DIRECTORY:-}" "${PRODUCT_ROOT:-}"; do
        [[ -n "${probe}" && -d "${probe}" ]] || continue
        if shared_parent="$(cd -- "${probe}/.." && pwd)"; then
            if [[ -d "${shared_parent}/share/core" && -d "${shared_parent}/share/config" ]]; then
                roots+=("${shared_parent}/share")
                return 0
            fi
        fi
    done
    return 0
}

locate_config_file() {
    local rel="$1"
    local root="" candidate=""
    local seen="|"
    local roots=()
    add_config_roots
    add_share_config_root
    for root in "${roots[@]}"; do
        [[ -n "${root}" ]] || continue
        [[ "${seen}" == *"|${root}|"* ]] && continue
        seen="${seen}${root}|"
        candidate="${root}/config/${rel}"
        if [[ -f "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    return 1
}

add_line() {
    local file="$1"
    local line="$2"
    local comment="${3:-}"
    if ! grep -qF "$line" "$file" 2>/dev/null; then
        [[ -n "$comment" ]] && echo "$comment" >>"$file"
        echo "$line" >>"$file"
    fi
}

copy_backup() {
    local file="$1"
    local backup="${file}.bak"
    [[ -f "$file" ]] || return 0
    [[ -f "$backup" ]] && return 0
    log_info "${INSTALL_WATCHER:-BASH}" "install.fs.info" "${file}"
    cp -a "$file" "$backup" && log_success "${INSTALL_WATCHER:-BASH}" "install.fs.success" "${backup}"
}

# A missing account name falls back to root.
apply_directory_owner() {
    local directory="$1"
    local mode="$2"
    local user="$3"
    local group="$4"
    local effective_user="$user"
    local effective_group="$group"
    mkdir -p "$directory"
    chmod "$mode" "$directory"
    if ! id -u "$effective_user" >/dev/null 2>&1; then
        effective_user="root"
    fi
    if ! getent group "$effective_group" >/dev/null 2>&1; then
        effective_group="root"
    fi
    chown "${effective_user}:${effective_group}" "$directory" 2>/dev/null || true
}

ensure_directory() {
    local mode="700"
    local user="root"
    local group="root"
    local directories=()

    while [ $# -gt 0 ]; do
        case "$1" in
            [0-9]*)
                mode="$1"
                shift
                break
                ;;
            *)
                directories+=("$1")
                shift
                ;;
        esac
    done

    if [ $# -ge 1 ]; then
        user="$1"
    fi
    if [ $# -ge 2 ]; then
        group="$2"
    fi

    local directory=""
    for directory in "${directories[@]}"; do
        apply_directory_owner "$directory" "$mode" "$user" "$group"
    done
}

check_user() {
    local user="$1"
    id "$user" >/dev/null 2>&1
}

set_usb_rule() {
    local key="$1" value="$2"
    # shellcheck disable=SC2154
    if grep -q "^${key}=" "${daemon_conf}"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "${daemon_conf}"
    else
        printf '%s=%s\n' "${key}" "${value}" >>"${daemon_conf}"
    fi
}

load_usb_rule() {
    local line key value
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" || "${line}" == \#* ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        set_usb_rule "${key}" "${value}"
    done <"$(locate_config_file service/usbguard/daemon.conf)"
}

read_file_mode() {
    local mode="$1"
    local path="$2"
    [[ -e "${path}" ]] || return 0
    chmod "${mode}" "${path}"
}

# Directory modes outside cron, secrets, and the log tree.
apply_tree_directory_modes() {
    local root="$1"
    chmod 755 "${root}"
    chown root:root "${root}"
    if [[ -d "${root}/.git" ]]; then
        chmod 700 "${root}/.git"
        chown root:root "${root}/.git"
    fi
    find "${root}" \
        -path "${root}/.git" -prune -o \
        -path "${root}/cron" -prune -o \
        -path "${root}/secrets" -prune -o \
        -path "${root}/log" -prune -o \
        -type d -exec chmod 755 {} + -exec chown root:root {} +
    find "${root}" \
        -path "${root}/.git" -prune -o \
        -path "${root}/cron" -prune -o \
        -path "${root}/secrets" -prune -o \
        -path "${root}/log" -prune -o \
        -type f -name '*.sh' -exec chmod 644 {} + -exec chown root:root {} +
}

apply_tree_script_modes() {
    local root="$1"
    local rel=""
    for rel in \
        liltress \
        script/configure.sh \
        script/run.sh \
        script/install.sh \
        core/mail/mail-test.sh \
        core/quarantine/restore.sh \
        service/aide/refresh-db.sh \
        service/apparmor/detect-and-apply.sh \
        service/rkhunter/refresh-db.sh \
        service/chkrootkit/ignore-log.sh \
        service/debsums/ignore-log.sh \
        system/sysctl/sysctl-apply.sh \
        system/sysctl/w-sysctl-apply.sh \
        service/unbound/nm-dispatcher.sh; do
        read_file_mode 755 "${root}/${rel}"
    done
    if [[ -d "${root}/service/cron/watchdogs" ]]; then
        find "${root}/service/cron/watchdogs" -type f -name '*.sh' \
            ! -name 'common.sh' ! -name 'scan-skip-lib.sh' \
            -exec chmod 755 {} +
    fi
    if [[ -d "${root}/service/vpn" ]]; then
        find "${root}/service/vpn" -type f -name '*.sh' -exec chmod 755 {} +
    fi
}

apply_tree_config_modes() {
    local root="$1"
    if [[ -d "${root}/config" ]]; then
        find "${root}/config" -type d -exec chmod 755 {} + -exec chown root:root {} +
        find "${root}/config" -type f ! -name 'secrets.conf' -exec chmod 644 {} + -exec chown root:root {} +
    fi
}

# A missing directory is left unchanged.
apply_secrets_directory_modes() {
    local root="$1"
    if [[ -d "${root}/secrets" ]]; then
        chmod 700 "${root}/secrets" || return 1
        chown root:root "${root}/secrets" || return 1
        find "${root}/secrets" -type f -exec chmod 600 {} + -exec chown root:root {} + || return 1
    fi
}

# A failed mode returns 1. Every command here checks its own status.
apply_tree_secret_modes() {
    local root="$1"
    if [[ -f "${root}/config/secrets.conf" ]]; then
        chmod 600 "${root}/config/secrets.conf" || return 1
        chown root:root "${root}/config/secrets.conf" || return 1
    fi
    apply_secrets_directory_modes "${root}" || return 1
    return 0
}

apply_tree_cron_modes() {
    local root="$1"
    local cron_user="$2"
    local log_mode="$3"
    local rel=""
    if [[ -d "${root}/cron" ]]; then
        chmod "${log_mode}" "${root}/cron"
        chown "root:${cron_user}" "${root}/cron"
    fi
    for rel in cron/cron_logs cron/security_logs cron/alerts cron/archives cron/quarantine; do
        if [[ -d "${root}/${rel}" ]]; then
            chmod "${log_mode}" "${root}/${rel}"
            chown "root:${cron_user}" "${root}/${rel}"
        fi
    done
}

apply_tree_log_modes() {
    local root="$1"
    if [[ -d "${root}/log" ]]; then
        find "${root}/log" -type d -exec chmod 750 {} + -exec chown root:root {} +
        find "${root}/log" -type f -exec chmod 640 {} + -exec chown root:root {} +
    fi
}

set_tree_modes() {
    local root="${CONFIG_BASE_DIRECTORY:?}"
    local cron_user="${CRON_USER:-}"
    local log_mode="750"
    [[ "${root}" == /opt/* && "${root}" != "/opt" ]] || return 1
    [[ -d "${root}" ]] || return 1
    apply_tree_directory_modes "${root}"
    apply_tree_script_modes "${root}"
    apply_tree_config_modes "${root}"
    apply_tree_secret_modes "${root}" || return $?
    if [[ -n "${cron_user}" ]] && id -u "${cron_user}" >/dev/null 2>&1; then
        log_mode="770"
    else
        cron_user="root"
    fi
    apply_tree_cron_modes "${root}" "${cron_user}" "${log_mode}"
    apply_tree_log_modes "${root}"
}

# A hyphen, a dot, an underscore, or a tilde stays literal.
pass_url_mark() {
    local byte="$1"
    [[ "${byte}" -eq 45 || "${byte}" -eq 46 || "${byte}" -eq 95 || "${byte}" -eq 126 ]]
}

# A digit or a letter stays literal.
pass_url_alnum() {
    local byte="$1"
    [[ ("${byte}" -ge 48 && "${byte}" -le 57) ||
        ("${byte}" -ge 65 && "${byte}" -le 90) ||
        ("${byte}" -ge 97 && "${byte}" -le 122) ]]
}

encode_url() {
    local s="$1" byte="" c="" out=""
    while IFS= read -r byte; do
        [[ -n "${byte}" ]] || continue
        if pass_url_mark "${byte}" || pass_url_alnum "${byte}"; then
            printf -v c '%b' "$(printf '\\%03o' "${byte}")"
            out+="${c}"
        else
            printf -v c "$(get_text install.02x)" "${byte}"
            out+="%${c}"
        fi
    done < <(printf '%s' "${s}" | od -An -tu1 -v | tr -s '[:space:]' '\n')
    printf '%s' "${out}"
}

persist_mode() {
    local mode="$1" path="$2" group="${3:-root}"
    [[ -e "${path}" ]] || return 0
    if dpkg-statoverride --list "${path}" >/dev/null 2>&1; then
        dpkg-statoverride --remove "${path}" >/dev/null
    fi
    dpkg-statoverride --update --add root "${group}" "${mode}" "${path}" >/dev/null
}
