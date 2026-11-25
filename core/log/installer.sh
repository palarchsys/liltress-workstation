#!/usr/bin/env bash
# =============================================================================
# File       : core/log/installer.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Ask one question and accept only a nested install tree.
# -----------------------------------------------------------------------------


# A free answer stays visible. The line matches the yes question.
# __answer stays local. The caller's name is the one printf -v writes.
ask_line() {
    local label="$1"
    local __var="$2"
    local __answer=""
    if [[ "${STEP_TREE:-0}" == "1" ]]; then
        render_step_branch
        printf '%s├── \e[34m?\e[0m %s : ' "$(render_step_bar)" "$(shorten_text "${label}" 60)" >&2
    else
        printf '\n         \e[34m%s\e[0m : ' "${label}" >&2
    fi
    if [[ ! -r /dev/tty ]]; then
        log_info "${INSTALL_WATCHER:-BASH}" "install.no-terminal"
        return 1
    fi
    IFS= read -r __answer </dev/tty || return 1
    printf -v "${__var}" '%s' "${__answer}"
}

ask() {
    ask_line "$1" "$2" || log_error "${INSTALL_WATCHER:-BASH}" "install.log.error.2"
}

# A title draws the yellow frame. Without one, the question stays in the step tree.
ask_yes() {
    local label="$1"
    local title="${2:-}"
    if [[ -n "${title}" ]]; then
        ask_yes_box "${label}" "${title}" || return 1
        return 0
    fi
    ask_yes_line "${label}"
}

ask_yes_line() {
    local label="$1"
    local answer=""
    if [[ "${STEP_TREE:-0}" == "1" ]]; then
        render_step_branch
        printf '%s├── \e[34m?\e[0m %s : ' "$(render_step_bar)" "$(shorten_text "${label}" 60)" >&2
    else
        printf '\n         \e[34m%s\e[0m : ' "${label}" >&2
    fi
    if [[ ! -r /dev/tty ]]; then
        log_info "${INSTALL_WATCHER:-BASH}" "install.no-terminal"
        return 1
    fi
    IFS= read -r answer </dev/tty || answer=""
    case "${answer}" in
        O | o) return 0 ;;
    esac
    return 1
}

ask_yes_box() {
    local label="$1"
    local title="$2"
    local width answer=""
    width="${#label}"
    if ((width < 12)); then
        width=12
    fi
    printf '\n' >&2
    show_title_box "${title}"
    printf '\n         \e[34m%*s\e[0m : ' "${width}" "${label}" >&2
    if [[ ! -r /dev/tty ]]; then
        log_info "${INSTALL_WATCHER:-BASH}" "install.no-terminal"
        return 1
    fi
    IFS= read -r answer </dev/tty || answer=""
    case "${answer}" in
        O | o) return 0 ;;
    esac
    return 1
}

# The path is absolute, present, and free of blanks.
check_plain_directory() {
    local path="$1"
    [[ -n "${path}" && "${path}" == /* && -d "${path}" ]] || return 1
    [[ "${path}" != *[[:space:]]* ]] || return 1
    return 0
}

# A product tree is nested and carries the marker plus the runner.
check_install_root_shape() {
    local root="$1"
    [[ "${root}" != *$'\n'* ]] || return 1
    case "${root}" in
        / | /opt | /usr | /bin | /sbin | /lib | /lib64 | /etc | /var | /home | /boot | /tmp | /root | /srv | /proc | /sys | /dev | /run)
            return 1
            ;;
    esac
    [[ "${root#/}" == */* ]] || return 1
    [[ -f "${root}/liltress" && -f "${root}/script/run.sh" ]] || return 1
    return 0
}

# The base stays outside the product tree.
check_install_base() {
    local root="$1"
    local base="$2"
    check_plain_directory "${base}" || return 1
    case "${base}/" in
        "${root}/"*) return 1 ;;
    esac
    return 0
}

check_installer_directory() {
    local root="$1"
    local base="$2"
    check_plain_directory "${root}" || return 1
    check_install_root_shape "${root}" || return 1
    check_install_base "${root}" "${base}" || return 1
    return 0
}

remove_installer_tree() {
    local root="" base=""
    root="$(cd -- "${INSTALL_DIRECTORY:?}" && pwd -P)" || return 1
    base="$(cd -- "${CONFIG_BASE_DIRECTORY:?}" && pwd -P)" || return 1
    check_installer_directory "${root}" "${base}" || return 1
    return 0
}

offer_remove_installer() {
    return 0
}
