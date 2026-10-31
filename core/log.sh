#!/usr/bin/env bash
# =============================================================================
# File       : core/log.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

set_color_blue()    { printf '\e[34m%s\e[0m\n' "$*" >&2; }
set_color_violet()  { printf '\e[35m%s\e[0m\n' "$*" >&2; }
set_color_red()     { printf '\e[31m%s\e[0m\n' "$*" >&2; }

get_fit_width() {
    local text="$1"
    local max="${2:-62}"
    local n="${#text}"
    if (( max < 4 || n <= max )); then
        if (( n > max && max > 0 )); then
            printf '%s' "${text:0:max}"
            return 0
        fi
        printf '%s' "$text"
        return 0
    fi
    printf '%s...' "${text:0:$((max - 3))}"
}

show_path() {
    local p="$1"
    case "$p" in
        /var/log|/var/log/*)
            printf '%s' "$p"
            ;;
        */log|*/log/*)
            printf '%s' "/log${p#*/log}"
            ;;
        *)
            printf '%s' "$p"
            ;;
    esac
}

shorten_logs_paths() {
    local rest="$1"
    local out="" pre path
    while [[ "$rest" == *"/log"* ]]; do
        pre="${rest%%/log*}"
        rest="${rest#*/log}"
        if [[ "$pre" == "/var" || "$pre" == */var ]]; then
            out+="${pre}/log"
            continue
        fi
        if [[ "$pre" =~ ^(.*[^/[:alnum:]._+~-])(/[[:alnum:]._+~/-]*)$ ]]; then
            out+="${BASH_REMATCH[1]}"
        elif [[ "$pre" == /* ]]; then
            :
        else
            out+="$pre"
        fi
        path="/log"
        if [[ "$rest" =~ ^(/[[:alnum:]._+~/-]*) ]]; then
            path+="${BASH_REMATCH[1]}"
            rest="${rest:${#BASH_REMATCH[1]}}"
        fi
        out+="$path"
    done
    printf '%s%s' "$out" "$rest"
}

emit_log() {
    local tag="$1"
    local msg="$2"
    local max="$3"
    if [[ -n "${G_LANGUAGE:-}" ]]; then
        load_text "${G_LANGUAGE}"
    fi
    if [[ "$tag" != "DEBUG" ]]; then
        msg="$(shorten_logs_paths "$msg")"
    fi
    if (( max > 0 )); then
        msg="$(get_fit_width "$msg" "$max")"
    fi
    case "$tag" in
        INFO)    printf '   \e[34m   [INFO]\e[0m  %s\n' "$msg" >&2 ;;
        SUCCESS) printf '   \e[32m[SUCCESS]\e[0m  %s\n' "$msg" >&2 ;;
        WARNING) printf '   \e[33m[WARNING]\e[0m  %s\n' "$msg" >&2 ;;
        DEBUG)   printf '   \e[90m  [DEBUG]\e[0m  %s\n' "$msg" >&2 ;;
    esac
}

log_escape_json() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "${value}"
}

log_emit_go() {
    local type="$1"
    local id="$2"
    local value="$3"
    printf 'GO{"type": "%s", "id": "%s", "value": "%s"}\n' \
        "${type}" "${id}" "$(log_escape_json "${value}")"
}

log_show() {
    local watcher="$1"
    local type="$2"
    local key="$3"
    shift 3
    local value=""
    value="$(get_text "${key}" "$@")"
    if [[ "${type}" != "title" ]]; then
        G_LOG_AFTER_TITLE=0
    fi
    if [[ "${watcher}" == "GO" ]]; then
        log_emit_go "${type}" "${key}" "${value}"
        if [[ "${type}" == "error" ]]; then
            exit 1
        fi
        return 0
    fi
    case "${type}" in
        info)    emit_log INFO "${value}" "${G_LOG_FIT_MAX:-62}" ;;
        success) emit_log SUCCESS "${value}" "${G_LOG_FIT_MAX:-62}" ;;
        warn)    emit_log WARNING "${value}" "${G_LOG_FIT_MAX:-62}" ;;
        debug)   emit_log DEBUG "${value}" 0 ;;
        title)
            if [[ "${G_LOG_AFTER_TITLE:-0}" != "1" ]]; then
                echo "" >&2
            fi
            set_color_blue "  -----------------------------------------------------------------------------"
            set_color_blue "   ${value}"
            set_color_blue "  -----------------------------------------------------------------------------"
            echo "" >&2
            G_LOG_AFTER_TITLE=1
            ;;
        subtitle)
            echo "" >&2
            set_color_blue "   ${value}"
            echo "" >&2
            ;;
        error)
            echo ""
            set_color_red "  -----------------------------------------------------------------------------"
            set_color_red "   ${value}"
            set_color_red "  -----------------------------------------------------------------------------"
            echo ""
            if [[ -n "${G_LOG_DIR:-}" ]]; then
                printf '%s\n' "${value}" >> "${G_LOG_DIR}/errors.log" 2>/dev/null || true
                log_show "${watcher}" info "log.journals" "${G_LOG_DIR}"
            fi
            exit 1
            ;;
    esac
}

log_info()     { log_show "${1:-BASH}" info "${2:-}" "${@:3}"; }
log_success()  { log_show "${1:-BASH}" success "${2:-}" "${@:3}"; }
log_warn()     { log_show "${1:-BASH}" warn "${2:-}" "${@:3}"; }
log_debug()    { log_show "${1:-BASH}" debug "${2:-}" "${@:3}"; }
log_title()    { log_show "${1:-BASH}" title "${2:-}" "${@:3}"; }
log_subtitle() {
    if [[ "${1:-BASH}" == "GO" ]]; then
        log_show "${1:-BASH}" subtitle "${2:-}" "${@:3}"
    fi
}
log_error()    { log_show "${1:-BASH}" error "${2:-}" "${@:3}"; }

require_root() {
    [[ "${EUID}" -eq 0 ]] || log_error "${INSTALL_WATCHER:-BASH}" "log.this-script-must-be-executed-with-sudo-or-as-roo"
}

set_step_visible() {

    if [[ "${G_STEP_BANNERS:-0}" -eq 1 ]]; then
        echo "" >&2
    fi
    G_STEP_BANNERS=1
    set_color_violet "═════════════════════════════════════════════════════════════════════════════════"
    set_color_violet " # $*"
    set_color_violet "═══ ↓ ↓ ═════════════════════════════════════════════════════════════════ ↓ ↓ ═══"
}

set_step_hidden() {
    echo "" >&2
    set_color_violet "═══ ↑ ↑ ═════════════════════════════════════════════════════════════════ ↑ ↑ ═══"
    set_color_violet " # $*"
    set_color_violet "═════════════════════════════════════════════════════════════════════════════════"
    echo "" >&2
}



check_debug_log() {
    [[ "${G_DEBUG_INSTALL_LOGS:-0}" == "1" || "${G_DEBUG_INSTALL_LOG:-0}" == "1" ]]
}

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
    local root="${G_INSTALL_DIRECTORY:-}"
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
    if [[ -n "${G_LOG_DIR:-}" ]]; then
        mkdir -p "${G_LOG_DIR}/steps"
        printf '%s\n' "${line}" >> "${G_LOG_DIR}/steps/INDEX.tsv"
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
    local root="${G_INSTALL_DIRECTORY:-.}"
    local stamp name kind old_umask os_label
    stamp="$(date '+%Y%m%d-%H%M%S')"
    kind="${S_SERVER_TYPE:-}"
    if [[ -z "${kind}" ]]; then
        if declare -F check_workstation >/dev/null 2>&1 && check_workstation; then
            kind="workstation"
        else
            kind="unknown"
        fi
    fi
    name="install-${stamp}-${kind}"

    G_LOG_DIR="${root}/log/${name}"
    G_LOG_SYS=""
    old_umask="$(umask)"
    umask 022
    mkdir -p "${G_LOG_DIR}/steps"
    G_LOG_FILE="${G_LOG_DIR}/install.log"
    : > "${G_LOG_FILE}"
    umask "${old_umask}"
    export G_LOG_DIR G_LOG_FILE G_LOG_SYS

    os_label="$(get_distribution_label)"
    printf '%s\n' "os          : ${os_label}" >> "${G_LOG_FILE}"

    {
        echo "$(get_text log.install-log "${G_PROJECT_NAME:-Liltress}")"
        echo "date        : $(date -Iseconds)"
        echo "hostname    : $(hostname 2>/dev/null || echo '?')"
        echo "os          : ${os_label}"
        echo "user        : ${CURRENT_USER:-}"
        echo "S_SERVER_TYPE : ${S_SERVER_TYPE:-}"
        echo "G_MODE_TEST   : ${G_MODE_TEST:-}"
        echo "S_MODE_DEV    : ${S_MODE_DEV:-}"
        echo "DIR         : ${root}"
        echo "log dir     : ${G_LOG_DIR}"
        echo "uname       : $(uname -a 2>/dev/null || true)"
    } | tee "${G_LOG_DIR}/meta.txt" >/dev/null

    exec > >(tee -a "${G_LOG_FILE}") 2>&1
    publish_repo_logs "${G_LOG_DIR}"
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
        echo "S_SERVER_TYPE=${S_SERVER_TYPE:-}"
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
    [[ -n "${G_LOG_DIR:-}" && -d "${G_LOG_DIR}" ]] || return 0
    [[ "${G_LOGS_COLLECTED:-0}" == "1" ]] && return 0
    G_LOGS_COLLECTED=1
    export G_LOGS_COLLECTED

    local snap="${G_LOG_DIR}/snapshot"
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
        echo "dossier : ${G_LOG_DIR}"
        echo "os          : $(get_distribution_label)"
        echo "$(get_text log.see-install-log-errors-log-and-steps-index-tsv)"
        echo "$(get_text log.software-snapshot-software-and-snapshot-journal)"
    } > "${snap}/COLLECTED.txt"

    log_info "${INSTALL_WATCHER:-BASH}" "install.log.info.2"
    publish_repo_logs "${G_LOG_DIR}"
}

install_exit() {
    local code=$?
    if [[ "${code}" -ne 0 ]]; then
        collect_install_log || true
    fi
    publish_repo_logs "${G_LOG_DIR:-}" || true
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
    root="$(cd -- "${G_INSTALL_DIRECTORY:?}" && pwd -P)" || return 1
    base="$(cd -- "${G_CONFIG_BASE_DIRECTORY:?}" && pwd -P)" || return 1
    check_installer_directory "${root}" "${base}" || return 1
    if [[ -f "${root}/core/mail.sh" ]]; then
        mail="${root}/core/mail.sh"
    elif [[ -f "${root}/../core/mail.sh" ]]; then
        mail="${root}/../core/mail.sh"
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

refresh_aide_after_remove() {
    local base="${G_CONFIG_BASE_DIRECTORY:-}"
    local log="/var/lib/aide/hf-remove-refresh.log"
    local aide_rc=0
    [[ -n "${base}" && -f /etc/aide/aide.conf ]] || return 0
    command -v aide >/dev/null 2>&1 || return 0
    grep -qF -- "${base}" /etc/aide/aide.conf || return 0
    log_info "${INSTALL_WATCHER:-BASH}" "install.log.info.3"
    mkdir -p /var/lib/aide || {
        log_warn "${INSTALL_WATCHER:-BASH}" "install.log.warn"
        return 0
    }
    rm -f /var/lib/aide/aide.db.new /var/lib/aide/aide.db.new.gz
    aide --config=/etc/aide/aide.conf --init >"${log}" 2>&1 || aide_rc=$?
    if [[ -f /var/lib/aide/aide.db.new.gz ]]; then
        if ! mv -f /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz; then
            log_warn "${INSTALL_WATCHER:-BASH}" "install.log.warn"
            return 0
        fi
        ln -sfn /var/lib/aide/aide.db.gz /var/lib/aide/aide.db || true
    elif [[ -f /var/lib/aide/aide.db.new ]]; then
        if ! mv -f /var/lib/aide/aide.db.new /var/lib/aide/aide.db; then
            log_warn "${INSTALL_WATCHER:-BASH}" "install.log.warn"
            return 0
        fi
    else
        log_warn "${INSTALL_WATCHER:-BASH}" "install.log.warn"
        G_LOG_FIT_MAX=0 log_warn "${INSTALL_WATCHER:-BASH}" "install.log.warn.5" "${log}"
        return 0
    fi
    if [[ "${aide_rc}" -ne 0 ]]; then
        log_warn "${INSTALL_WATCHER:-BASH}" "install.log.warn.6" "Code aide ${aide_rc}. La base produite est en service."
    fi
    log_success "${INSTALL_WATCHER:-BASH}" "install.log.success"
    return 0
}

offer_remove_installer() {
    local root="" base="" answer="" rc=0
    if [[ "${G_MODE_TEST:-0}" == "1" || "${S_MODE_DEV:-0}" == "1" ]]; then
        return 0
    fi
    if [[ ! -r /dev/tty ]]; then
        log_warn "${INSTALL_WATCHER:-BASH}" "install.log.warn.7"
        return 0
    fi
    root="$(cd -- "${G_INSTALL_DIRECTORY:?}" && pwd -P)" || {
        log_warn "${INSTALL_WATCHER:-BASH}" "install.log.warn.8"
        return 0
    }
    base="${G_CONFIG_BASE_DIRECTORY:-}"

    log_title "${INSTALL_WATCHER:-BASH}" "install.log.title"
    log_info "${INSTALL_WATCHER:-BASH}" "install.log.info.4"
    G_LOG_FIT_MAX=0 log_info "${INSTALL_WATCHER:-BASH}" "install.log.info.5" "${root}"
    while true; do
        ask "Supprimer" answer
        answer="${answer#"${answer%%[![:space:]]*}"}"
        answer="${answer%"${answer##*[![:space:]]}"}"
        case "${answer,,}" in
            y) break ;;
            n) return 0 ;;
            *) log_warn "${INSTALL_WATCHER:-BASH}" "install.log.warn.9";;
        esac
    done
    log_info "${INSTALL_WATCHER:-BASH}" "install.log.info.6"
    remove_installer_tree || rc=$?
    echo "" >&2
    case "${rc}" in
        0)
            log_success "${INSTALL_WATCHER:-BASH}" "install.log.success.2"
            log_info "${INSTALL_WATCHER:-BASH}" "install.log.info.7"
            if [[ ! -e "${root}/liltress" && ! -e "${base}/src/liltress" ]]; then
                log_info "${INSTALL_WATCHER:-BASH}" "install.log.info.8"
            fi
            refresh_aide_after_remove || true
            ;;
        1)
            log_warn "${INSTALL_WATCHER:-BASH}" "install.log.warn.10"
            ;;
        2)
            log_warn "${INSTALL_WATCHER:-BASH}" "install.log.warn.11"
            ;;
        3)
            log_warn "${INSTALL_WATCHER:-BASH}" "install.log.warn.12"
            refresh_aide_after_remove || true
            ;;
        *)
            log_warn "${INSTALL_WATCHER:-BASH}" "install.log.warn.13"
            refresh_aide_after_remove || true
            ;;
    esac
    return 0
}

collect_manual() {
    local root="${G_INSTALL_DIRECTORY:-.}"
    local stamp name old_umask
    stamp="$(date '+%Y%m%d-%H%M%S')"
    name="snapshot-${stamp}-$(hostname -s 2>/dev/null || hostname)"
    S_SERVER_TYPE="${S_SERVER_TYPE:-manual}"
    G_LOG_DIR="${root}/log/${name}"
    G_LOG_SYS=""
    old_umask="$(umask)"
    umask 022
    mkdir -p "${G_LOG_DIR}/snapshot"
    umask "${old_umask}"
    export G_LOG_DIR G_LOG_SYS S_SERVER_TYPE
    unset G_LOGS_COLLECTED
    collect_install_log
    log_info "${INSTALL_WATCHER:-BASH}" "install.log.info.9" "${G_LOG_DIR}"
}

get_log_copy_limit() {
    printf '%s\n' 8388608
}

log_note() {
    local snap="${G_LOG_DIR:-}"
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
    if [[ -n "${G_CONFIG_BASE_DIRECTORY:-}" ]]; then
        copy_log_tree "${G_CONFIG_BASE_DIRECTORY}/cron/cron_logs" "${dest}"
        copy_log_tree "${G_CONFIG_BASE_DIRECTORY}/cron/security_logs" "${dest}"
        copy_log_tree "${G_CONFIG_BASE_DIRECTORY}/cron/alerts" "${dest}"
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

# Placeholders are {1}, {2}, … The whole number is read, so {10} is not {1}.
# The argument is inserted as text. The catalog is not evaluated.

check_language() {
    case "${1:-}" in
        en|fr|de|es) return 0 ;;
        *) return 1 ;;
    esac
}

collect_text_dirs() {
    local -n dir_dest="$2"
    local lang="$1"
    local text_here="" text_product="" text_base="" candidate="" resolved="" seen="|"
    text_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    text_product="${G_PRODUCT_ROOT:-}"
    if [[ -z "${text_product}" ]]; then
        text_product="$(cd -- "${text_here}/.." && pwd)"
    fi
    if declare -F get_product_base >/dev/null 2>&1; then
        text_base="$(get_product_base)"
    elif [[ -n "${W_BASE:-}" ]]; then
        text_base="${W_BASE}"
    elif [[ -n "${G_CONFIG_BASE_DIRECTORY:-}" ]]; then
        text_base="${G_CONFIG_BASE_DIRECTORY}"
    elif [[ -n "${G_BASE:-}" ]]; then
        text_base="${G_BASE}"
    else
        text_base="/opt/liltress"
    fi
    dir_dest=()
    local -a text_candidates=(
        "${text_here}/text/${lang}"
        "${text_product}/core/text/${lang}"
        "${text_base}/src/core/text/${lang}"
        "${text_base}/core/text/${lang}"
        "${G_INSTALL_DIRECTORY:-}/core/text/${lang}"
        "${text_product}/locale/${lang}"
        "${text_base}/src/locale/${lang}"
        "${text_base}/locale/${lang}"
    )
    if [[ -n "${G_TEXT_DIR:-}" ]]; then
        text_candidates+=("${G_TEXT_DIR}/${lang}")
    fi
    for candidate in "${text_candidates[@]}"; do
        [[ -n "${candidate}" && -d "${candidate}" ]] || continue
        resolved="$(cd -- "${candidate}" && pwd -P)" || continue
        [[ "${seen}" == *"|${resolved}|"* ]] && continue
        seen+="${resolved}|"
        dir_dest+=("${resolved}")
    done
}

read_text_file() {
    local file="$1"
    local -n text_dest="$2"
    local line="" key="" value="" open=0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^\[([a-z][a-z0-9-]*(\.[a-z0-9-]+)+)\]$ ]]; then
            if [[ "${open}" -eq 1 ]]; then
                while [[ "${value}" == *$'\n' ]]; do
                    value="${value%$'\n'}"
                done
                text_dest["${key}"]="${value}"
            fi
            key="${BASH_REMATCH[1]}"
            value=""
            open=1
            continue
        fi
        if [[ "${open}" -eq 0 ]]; then
            continue
        fi
        value+="${line}"$'\n'
    done < "${file}"
    if [[ "${open}" -eq 1 ]]; then
        while [[ "${value}" == *$'\n' ]]; do
            value="${value%$'\n'}"
        done
        text_dest["${key}"]="${value}"
    fi
}

load_text() {
    local lang="${1:-${G_LANGUAGE:-en}}"
    local dir="" file="" joined="" key=""
    if ! check_language "${lang}"; then
        lang="en"
    fi
    if [[ -z "${G_LANGUAGE:-}" ]]; then
        G_LANGUAGE="en"
    fi
    if [[ "${G_TEXT_LANGUAGE:-}" == "${lang}" && "${G_TEXT_READY:-0}" == "1" && "${G_TEXT_DIR_LOADED:-}" == "${G_TEXT_DIR:-}" ]]; then
        export G_LANGUAGE
        return 0
    fi
    declare -gA G_TEXT_ENGLISH=()
    declare -gA G_TEXT_SELECTED=()
    local -a english_dirs=() selected_dirs=()
    collect_text_dirs en english_dirs
    if [[ "${lang}" == "en" ]]; then
        selected_dirs=("${english_dirs[@]}")
    else
        collect_text_dirs "${lang}" selected_dirs
    fi
    for dir in "${english_dirs[@]}"; do
        for file in "${dir}"/*.txt; do
            [[ -f "${file}" ]] || continue
            read_text_file "${file}" G_TEXT_ENGLISH
        done
    done
    if [[ "${lang}" == "en" ]]; then
        for key in "${!G_TEXT_ENGLISH[@]}"; do
            G_TEXT_SELECTED["${key}"]="${G_TEXT_ENGLISH[${key}]}"
        done
    else
        for dir in "${selected_dirs[@]}"; do
            for file in "${dir}"/*.txt; do
                [[ -f "${file}" ]] || continue
                read_text_file "${file}" G_TEXT_SELECTED
            done
        done
    fi
    joined="$(IFS=:; printf '%s' "${english_dirs[*]}")"
    G_TEXT_EN_DIRS="${joined}"
    joined="$(IFS=:; printf '%s' "${selected_dirs[*]}")"
    G_TEXT_LANG_DIRS="${joined}"
    G_TEXT_LANGUAGE="${lang}"
    G_TEXT_DIR_LOADED="${G_TEXT_DIR:-}"
    G_TEXT_READY=1
    export G_LANGUAGE G_TEXT_EN_DIRS G_TEXT_LANG_DIRS
}

apply_text() {
    local text="$1"
    shift
    local -a text_args=("$@")
    local text_out="" text_rest="${text}" text_head="" text_num="" text_mark=""
    while [[ "${text_rest}" == *'{'* ]]; do
        text_head="${text_rest%%\{*}"
        text_rest="${text_rest#*\{}"
        text_out+="${text_head}"
        if [[ "${text_rest}" =~ ^([0-9]+)\} ]]; then
            text_num="${BASH_REMATCH[1]}"
            text_mark="${BASH_REMATCH[0]}"
            text_rest="${text_rest#"${text_mark}"}"
            if (( text_num >= 1 && text_num <= ${#text_args[@]} )); then
                text_out+="${text_args[$((text_num - 1))]}"
            else
                text_out+="{${text_num}}"
            fi
        else
            text_out+="{"
        fi
    done
    printf '%s' "${text_out}${text_rest}"
}

get_text() {
    local key="$1"
    shift
    local lang="${G_LANGUAGE:-en}" text=""
    if ! check_language "${lang}"; then
        lang="en"
    fi
    if [[ "${G_TEXT_LANGUAGE:-}" != "${lang}" || "${G_TEXT_READY:-0}" != "1" || "${G_TEXT_DIR_LOADED:-}" != "${G_TEXT_DIR:-}" ]]; then
        load_text "${lang}"
    fi
    if [[ -n "${G_TEXT_SELECTED[${key}]+x}" ]]; then
        text="${G_TEXT_SELECTED[${key}]}"
    elif [[ -n "${G_TEXT_ENGLISH[${key}]+x}" ]]; then
        text="${G_TEXT_ENGLISH[${key}]}"
    else
        printf '%s' "${key}"
        return 0
    fi
    if [[ "$#" -eq 0 ]]; then
        printf '%s' "${text}"
        return 0
    fi
    apply_text "${text}" "$@"
}

read_text_record() {
    local lang="$1" key="$2"
    local -a dirs=()
    local dir="" file="" line="" current="" value="" found=""
    collect_text_dirs "${lang}" dirs
    for dir in "${dirs[@]}"; do
        for file in "${dir}"/*.txt; do
            [[ -f "${file}" ]] || continue
            current=""
            value=""
            while IFS= read -r line || [[ -n "${line}" ]]; do
                if [[ "${line}" =~ ^\[([a-z][a-z0-9-]*(\.[a-z0-9-]+)+)\]$ ]]; then
                    if [[ "${current}" == "${key}" ]]; then
                        found="${value}"
                        while [[ "${found}" == *$'\n' ]]; do
                            found="${found%$'\n'}"
                        done
                    fi
                    current="${BASH_REMATCH[1]}"
                    value=""
                    continue
                fi
                if [[ -n "${current}" ]]; then
                    value+="${line}"$'\n'
                fi
            done < "${file}"
            if [[ "${current}" == "${key}" ]]; then
                found="${value}"
                while [[ "${found}" == *$'\n' ]]; do
                    found="${found%$'\n'}"
                done
            fi
        done
    done
    printf '%s' "${found}"
}

read_language_file() {
    local file="$1" line="" value=""
    if [[ -z "${G_LANGUAGE:-}" ]]; then
        G_LANGUAGE="en"
    fi
    if [[ -f "${file}" ]]; then
        line="$(grep -E '^G_LANGUAGE=' -- "${file}" | head -n 1 || true)"
        if [[ -n "${line}" ]]; then
            value="${line#G_LANGUAGE=}"
            value="${value%\"}"
            value="${value#\"}"
            value="${value%\'}"
            value="${value#\'}"
            if check_language "${value}"; then
                G_LANGUAGE="${value}"
            elif [[ -z "${value}" ]]; then
                G_LANGUAGE="en"
            fi
        fi
    fi
    if ! check_language "${G_LANGUAGE}"; then
        G_LANGUAGE="en"
    fi
    export G_LANGUAGE
    load_text "${G_LANGUAGE}"
}

# Command substitution starts a subshell. A catalog loaded there is discarded.
# Load once in this shell so later lookups reuse the arrays.
load_product_text() {
    local lang_file=""
    if [[ -n "${G_PRODUCT_ROOT:-}" && -f "${G_PRODUCT_ROOT}/config/global.conf" ]]; then
        lang_file="${G_PRODUCT_ROOT}/config/global.conf"
    elif [[ -n "${G_INSTALL_DIRECTORY:-}" && -f "${G_INSTALL_DIRECTORY}/config/global.conf" ]]; then
        lang_file="${G_INSTALL_DIRECTORY}/config/global.conf"
    fi
    if [[ -n "${lang_file}" ]]; then
        read_language_file "${lang_file}"
        return 0
    fi
    if [[ -n "${G_LANGUAGE:-}" ]]; then
        load_text "${G_LANGUAGE}"
    fi
}

ask_language() {
    local current="${G_LANGUAGE:-en}" hint="" choice="" lang=""
    check_language "${current}" || current="en"
    for lang in en fr de es; do
        hint="$(read_text_record "${lang}" "configure.language.hint")"
        if [[ -z "${hint}" ]]; then
            hint="${lang}"
        fi
        printf '%s\n' "${hint}" >&2
    done
    printf '%s\n' "1 en" >&2
    printf '%s\n' "2 fr" >&2
    printf '%s\n' "3 de" >&2
    printf '%s\n' "4 es" >&2
    IFS= read -r choice || choice=""
    choice="${choice#"${choice%%[![:space:]]*}"}"
    choice="${choice%"${choice##*[![:space:]]}"}"
    case "${choice}" in
        "") G_LANGUAGE="${current}" ;;
        1|en|EN) G_LANGUAGE="en" ;;
        2|fr|FR) G_LANGUAGE="fr" ;;
        3|de|DE) G_LANGUAGE="de" ;;
        4|es|ES) G_LANGUAGE="es" ;;
        *) G_LANGUAGE="en" ;;
    esac
    export G_LANGUAGE
    G_TEXT_READY=0
    load_text "${G_LANGUAGE}"
}

load_product_text
