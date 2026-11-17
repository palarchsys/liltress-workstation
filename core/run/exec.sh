#!/usr/bin/env bash
# =============================================================================
# File       : core/run/exec.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Run one install step, an apt command, or the steps named by the plan.
# -----------------------------------------------------------------------------


# The caller owns shown_python and reads it after this call.
show_python_directory() {
    local candidate="$1"
    shown_python=0
    [[ -n "${candidate}" && -d "${candidate}" ]] || return 0
    (cd -- "${candidate}" && pwd -P)
    shown_python=1
    return 0
}

# The shared directory is printed as given, without resolving links.
show_share_python() {
    local dir="$1"
    shown_python=0
    if [[ ! -d "${dir}/share/python" ]]; then
        return 0
    fi
    printf '%s\n' "${dir}/share/python"
    shown_python=1
    return 0
}

locate_python_dir() {
    local dir="" hops=0 candidate="" shown_python=0
    for candidate in \
        "${CONFIG_BASE_DIRECTORY:-}/python" \
        "${BASE:-}/python" \
        "${INSTALL_DIRECTORY:-}/python" \
        "${INSTALL_DIRECTORY:-}/../share/python"; do
        show_python_directory "${candidate}"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
    done
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        show_share_python "${dir}"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
        show_python_directory "${dir}/python"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

# GO streams each line. The caller owns nothing from this path.
run_watch_go() {
    local watcher="$1"
    local error_key="$2"
    local stream_id="$3"
    shift 3
    local fifo="" pid="" line="" exit_code=0
    fifo="$(mktemp -u)"
    mkfifo "${fifo}"
    "$@" >"${fifo}" 2>&1 &
    pid=$!
    while IFS= read -r line; do
        log_emit_go stream "${stream_id}" "${line}"
    done <"${fifo}"
    wait "${pid}" || exit_code=$?
    rm -f "${fifo}"
    if [[ "${exit_code}" -ne 0 ]]; then
        log_error "${watcher}" "${error_key}" "${exit_code}"
    fi
    return 0
}

run_watch() {
    local watcher="$1"
    local error_key="$2"
    shift 2
    local output="" exit_code=0 stream_id=""
    stream_id="${error_key%.error}.stream"
    if [[ "${watcher}" == "GO" ]]; then
        run_watch_go "${watcher}" "${error_key}" "${stream_id}" "$@"
        return 0
    fi
    output=$("$@" 2>&1) || exit_code=$?
    if [[ -n "${INSTALL_LOG_FILE:-}" && -n "${output}" ]]; then
        printf '%s\n' "${output}" >>"${INSTALL_LOG_FILE}"
    fi
    if [[ "${exit_code}" -ne 0 ]]; then
        log_error "${watcher}" "${error_key}" "${output:-exit ${exit_code}}"
    fi
}

run_silent() {
    local watcher="$1"
    local error_key="$2"
    shift 2
    run_watch "${watcher}" "${error_key}" "$@"
}

run_quiet() {
    local watcher="$1"
    local error_key="$2"
    shift 2
    run_watch "${watcher}" "${error_key}" "$@"
}

run_optional() {
    local watcher="$1"
    local error_key="$2"
    shift 2
    local line="" output="" exit_code=0 stream_id=""
    stream_id="${error_key%.error}.stream"
    if [[ "${watcher}" == "GO" ]]; then
        while IFS= read -r line; do
            log_emit_go stream "${stream_id}" "${line}"
        done < <("$@" 2>&1) || true
        return 0
    fi
    output=$("$@" 2>&1) || exit_code=$?
    if [[ "${exit_code}" -ne 0 && -n "${output}" ]]; then
        log_debug "${watcher}" "install.exec.debug" "${output}"
    fi
    return 0
}

# The caller owns cmd_output and exit_code.
run_apt_once() {
    local watcher="$1"
    local error_key="$2"
    shift 2
    local fifo="" pid="" line=""
    exit_code=0
    if [[ "${watcher}" == "GO" ]]; then
        fifo="$(mktemp -u)"
        mkfifo "${fifo}"
        cmd_output=""
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get "$@" >"${fifo}" 2>&1 </dev/null &
        pid=$!
        while IFS= read -r line; do
            log_emit_go stream "${error_key%.error}.stream" "${line}"
            cmd_output+="${line}"$'\n'
        done <"${fifo}"
        wait "${pid}" || exit_code=$?
        rm -f "${fifo}"
        return 0
    fi
    cmd_output=$(DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get "$@" </dev/null 2>&1) || exit_code=$?
    return 0
}

run_silent_apt() {
    local watcher="$1"
    local command="$2"
    local error_key="$3"
    local -a args=()
    local cmd_output="" exit_code=0 attempt=0 max_attempts=30 refreshed=0
    read -r -a args <<<"${command}"
    sleep 1
    while [[ "${attempt}" -lt "${max_attempts}" ]]; do
        run_apt_once "${watcher}" "${error_key}" "${args[@]}"
        if [[ "${exit_code}" -eq 0 ]]; then
            return 0
        fi
        if echo "${cmd_output}" | grep -qE "Could not get lock|verrou|lock-frontend|unattended-upgr"; then
            attempt=$((attempt + 1))
            sleep 2
            continue
        fi
        if [[ "${refreshed}" -eq 0 ]] && echo "${cmd_output}" | grep -qE '404  Not Found|Failed to fetch|Impossible de récupérer'; then
            refreshed=1
            DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get update </dev/null >/dev/null 2>&1 || true
            continue
        fi
        log_error "${watcher}" "${error_key}" "${cmd_output}"
    done
    log_error "${watcher}" "log.timeout-verrou-apt-busy-always-after-attempts" "${max_attempts}"
}

# The caller owns step_exit.
run_one_step() {
    local dir_install_path="$1"
    local server_type="$2"
    local step="$3"
    local full_path="${dir_install_path}/${step}"
    local step_log=""
    if [[ ! -f "$full_path" ]]; then
        log_error "${INSTALL_WATCHER:-BASH}" "log.file-not-found" "$full_path"
        exit 1
    fi
    step_exit=0
    step_log=""
    if [[ -n "${INSTALL_LOG_DIR:-}" ]]; then
        step_log="${INSTALL_LOG_DIR}/steps/$(echo "$step" | tr '/' '-').log"
        mkdir -p "${INSTALL_LOG_DIR}/steps"
        set +e
        if [[ "${INSTALL_WATCHER:-BASH}" != "GO" ]]; then
            SECTION_OPEN="${SECTION_OPEN:-0}" SECTION_HAD_STEP="${SECTION_HAD_STEP:-0}" STEP_LABEL="${step}" bash "$full_path" "${INSTALL_WATCHER:-BASH}" "$dir_install_path" "$server_type" 2>&1 | tee -a "$step_log"
        else
            bash "$full_path" "${INSTALL_WATCHER:-BASH}" "$dir_install_path" "$server_type" 2>&1 | tee -a "$step_log"
        fi
        step_exit=${PIPESTATUS[0]}
        set -e
        mark_section_step
        log_index_append "${step}" "${step_exit}" "${step_log}"
        publish_repo_logs "${INSTALL_LOG_DIR}"
        return 0
    fi
    set +e
    if [[ "${INSTALL_WATCHER:-BASH}" != "GO" ]]; then
        SECTION_OPEN="${SECTION_OPEN:-0}" SECTION_HAD_STEP="${SECTION_HAD_STEP:-0}" STEP_LABEL="${step}" bash "$full_path" "${INSTALL_WATCHER:-BASH}" "$dir_install_path" "$server_type"
    else
        bash "$full_path" "${INSTALL_WATCHER:-BASH}" "$dir_install_path" "$server_type"
    fi
    step_exit=$?
    set -e
    mark_section_step
    log_index_append "${step}" "${step_exit}" ""
}

run_step() {
    local dir_install_path="$1"
    local server_type=""
    shift

    if [[ $# -gt 0 ]]; then
        case "$1" in
            *.sh) ;;
            *)
                server_type="$1"
                shift
                ;;
        esac
    fi
    local -a steps=("$@")
    local step step_exit=0

    [[ ${#steps[@]} -eq 0 ]] && {
        log_error "${INSTALL_WATCHER:-BASH}" "log.no-step-provided"
        return 1
    }

    [[ -z "$dir_install_path" || ! -d "$dir_install_path" ]] && {
        log_error "${INSTALL_WATCHER:-BASH}" "log.dir-install-path-invalid" "$dir_install_path"
        return 1
    }

    for step in "${steps[@]}"; do
        run_one_step "${dir_install_path}" "${server_type}" "${step}"
        if [[ $step_exit -ne 0 ]]; then
            exit $step_exit
        fi
    done

    return 0
}

# The caller owns seen_category.
show_plan_category() {
    local category="$1"
    [[ "${category}" == "${seen_category}" ]] && return 0
    seen_category="${category}"
    if [[ "${INSTALL_WATCHER:-BASH}" == "GO" ]]; then
        log_title "${INSTALL_WATCHER}" "${category}"
    else
        set_step_visible "$(get_text "${category}")"
    fi
}

# The caller owns plan_ready. 1 means this row runs.
pass_plan_condition() {
    local when_var="$1"
    local when_eq="$2"
    local value=""
    plan_ready=1
    [[ -n "${when_var}" ]] || return 0
    case "${when_var}" in
        MAIL_ALERTS | SERVER_TYPE | MODE_TEST | MODE_DEV) ;;
        *) log_error "${INSTALL_WATCHER:-BASH}" "log.condition.rejected" "${when_var}" ;;
    esac
    value="${!when_var:-}"
    if [[ "${value}" != "${when_eq}" ]]; then
        plan_ready=0
    fi
    return 0
}

run_plan_target() {
    local root="$1"
    local profile="$2"
    local kind="$3"
    local target="$4"
    local envspec="$5"
    if [[ "${kind}" == "path" ]]; then
        if [[ -n "${envspec}" ]]; then
            run_install_step_env "${root}" "${profile}" "${target}" "${envspec}"
        elif [[ -n "${profile}" ]]; then
            run_step "${root}" "${profile}" "${target}"
        else
            run_step "${root}" "${target}"
        fi
        return 0
    fi
    case "${target}" in
        reboot-notice | http-check)
            run_install_action "${target}"
            ;;
        *)
            if [[ "${INSTALL_WATCHER:-BASH}" != "GO" ]]; then
                open_step_tree "$(get_text log.execution-of "${target}")"
            fi
            run_install_action "${target}"
            close_step_tree
            mark_section_step
            ;;
    esac
}

# installation.json names the steps. The allowed conditions are the flags run.sh already reads.
run_install_plan() {
    local root="$1"
    local plan="$2"
    local profile="${3:-}"
    local category="" id="" kind="" target="" when_var="" when_eq="" envspec="" seen_category="" plan_ready=1
    [[ -f "${plan}" ]] || log_error "${INSTALL_WATCHER:-BASH}" "log.file-not-found" "${plan}"
    while IFS=$'\x1f' read -r category id kind target when_var when_eq envspec || [[ -n "${id}" ]]; do
        [[ -n "${id}" ]] || continue
        show_plan_category "${category}"
        pass_plan_condition "${when_var}" "${when_eq}"
        if [[ "${plan_ready}" -eq 0 ]]; then
            continue
        fi
        run_plan_target "${root}" "${profile}" "${kind}" "${target}" "${envspec}"
    done < <(
        python3 "$(locate_python_dir)/install-plan.py" steps "${plan}"
    )
}

run_install_step_env() {
    local root="$1"
    local profile="$2"
    local step="$3"
    local envspec="$4"
    local pair="" key="" val=""
    (
        local IFS=','
        for pair in ${envspec}; do
            key="${pair%%=*}"
            val="${pair#*=}"
            case "${key}" in
                *) exit 1 ;;
            esac
            printf -v "${key}" '%s' "${val}"
            # shellcheck disable=SC2163
            export "${key}"
        done
        if [[ -n "${profile}" ]]; then
            run_step "${root}" "${profile}" "${step}"
        else
            run_step "${root}" "${step}"
        fi
    ) || exit $?
}
