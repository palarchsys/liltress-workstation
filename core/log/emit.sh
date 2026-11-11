#!/usr/bin/env bash
# =============================================================================
# File       : core/log/emit.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================


emit_log() {
    local tag="$1"
    local msg="$2"
    local max="$3"
    if [[ -n "${LANGUAGE:-}" ]]; then
        load_text "${LANGUAGE}"
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
    if [[ "${watcher}" == "GO" ]]; then
        log_emit_go "${type}" "${key}" "${value}"
        if [[ "${type}" == "error" ]]; then
            exit 1
        fi
        return 0
    fi
    case "${type}" in
        info|debug) note_bash info "${value}" ;;
        success)    note_bash success "${value}" ;;
        warn)       note_bash warn "${value}" ;;
        fault)      note_bash fault "${value}" ;;
        title)
            step_flush_branch
            show_title_box "${value}"
            ;;
        error)
            note_bash error "${value}"
            if [[ -n "${INSTALL_LOG_DIR:-}" ]]; then
                printf '%s\n' "${value}" >> "${INSTALL_LOG_DIR}/errors.log" 2>/dev/null || true
            fi
            STEP_TREE=0
            STEP_PENDING=""
            show_section_close
            show_title_box "$(get_text log.installation-could-not-finish)"
            printf '\n' >&2
            if [[ -n "${INSTALL_LOG_DIR:-}" ]]; then
                note_bash info "$(get_text log.journals "${INSTALL_LOG_DIR}")"
            fi
            printf '\n' >&2
            exit 1
            ;;
    esac
}

log_info()     { log_show "${1:-BASH}" info    "${2:-}" "${@:3}"; }

log_success()  { log_show "${1:-BASH}" success "${2:-}" "${@:3}"; }

log_warn()     { log_show "${1:-BASH}" warn    "${2:-}" "${@:3}"; }

log_debug()    { log_show "${1:-BASH}" debug   "${2:-}" "${@:3}"; }

log_title()    { log_show "${1:-BASH}" title   "${2:-}" "${@:3}"; }

log_error()    { log_show "${1:-BASH}" error   "${2:-}" "${@:3}"; }

require_root() {
    [[ "${EUID}" -eq 0 ]] || log_error "${INSTALL_WATCHER:-BASH}" "log.this-script-must-be-executed-with-sudo-or-as-roo"
}

set_step_visible() {
    close_step_tree
    if [[ "${SECTION_OPEN:-0}" == "1" ]]; then
        show_section_close
    fi
    show_section_open "$*"
}

set_step_hidden() {
    close_step_tree
    if [[ "${SECTION_OPEN:-0}" == "1" ]]; then
        show_section_close
    fi
    show_title_box "$*"
    printf '\n' >&2
}
