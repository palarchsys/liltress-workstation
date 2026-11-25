#!/usr/bin/env bash
# =============================================================================
# File       : core/log/emit.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Show one catalog line in the journal or as a GO line.
# -----------------------------------------------------------------------------


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
    if ((max > 0)); then
        msg="$(get_fit_width "$msg" "$max")"
    fi
    case "$tag" in
        INFO) printf '   \e[34m   [INFO]\e[0m  %s\n' "$msg" >&2 ;;
        SUCCESS) printf '   \e[32m[SUCCESS]\e[0m  %s\n' "$msg" >&2 ;;
        WARNING) printf '   \e[33m[WARNING]\e[0m  %s\n' "$msg" >&2 ;;
        DEBUG) printf '   \e[90m  [DEBUG]\e[0m  %s\n' "$msg" >&2 ;;
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

# The section closes and the failure box follows.
show_log_failure() {
    local value="$1"
    if [[ -n "${INSTALL_LOG_DIR:-}" ]]; then
        printf '%s\n' "${value}" >>"${INSTALL_LOG_DIR}/errors.log" 2>/dev/null || true
    fi
    STEP_TREE=0
    STEP_PENDING=""
    show_section_close
    show_title_box "$(get_text log.installation-could-not-finish)"
    printf '\n' >&2
    if [[ -n "${INSTALL_LOG_DIR:-}" ]]; then
        record_bash_note info "$(get_text log.journals "${INSTALL_LOG_DIR}")"
    fi
    printf '\n' >&2
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
        info | debug) record_bash_note info "${value}" ;;
        success) record_bash_note success "${value}" ;;
        warn) record_bash_note warn "${value}" ;;
        fault) record_bash_note fault "${value}" ;;
        title)
            render_step_branch
            show_title_box "${value}"
            ;;
        error)
            record_bash_note error "${value}"
            show_log_failure "${value}"
            exit 1
            ;;
    esac
}

log_info() { log_show "${1:-BASH}" info "${2:-}" "${@:3}"; }

log_success() { log_show "${1:-BASH}" success "${2:-}" "${@:3}"; }

log_warn() { log_show "${1:-BASH}" warn "${2:-}" "${@:3}"; }

log_debug() { log_show "${1:-BASH}" debug "${2:-}" "${@:3}"; }

log_title() { log_show "${1:-BASH}" title "${2:-}" "${@:3}"; }

log_error() { log_show "${1:-BASH}" error "${2:-}" "${@:3}"; }

require_root() {
    [[ "${EUID}" -eq 0 ]] || log_error "${INSTALL_WATCHER:-BASH}" "log.this-script-must-be-executed-with-sudo-or-as-roo"
}

set_step_visible() {
    finish_step_tree
    if [[ "${SECTION_OPEN:-0}" == "1" ]]; then
        show_section_close
    fi
    show_section_open "$*"
}

set_step_hidden() {
    finish_step_tree
    if [[ "${SECTION_OPEN:-0}" == "1" ]]; then
        show_section_close
    fi
    show_title_box "$*"
    printf '\n' >&2
}
