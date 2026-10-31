#!/usr/bin/env bash
# =============================================================================
# File       : core/exec.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

run_watch() {
    local watcher="$1"
    local error_key="$2"
    shift 2
    local line="" output="" exit_code=0 stream_id=""
    stream_id="${error_key%.error}.stream"
    if [[ "${watcher}" == "GO" ]]; then
        local fifo="" pid=""
        fifo="$(mktemp -u)"
        mkfifo "${fifo}"
        "$@" >"${fifo}" 2>&1 &
        pid=$!
        while IFS= read -r line; do
            log_emit_go stream "${stream_id}" "${line}"
        done < "${fifo}"
        wait "${pid}" || exit_code=$?
        rm -f "${fifo}"
        if [[ "${exit_code}" -ne 0 ]]; then
            log_error "${watcher}" "${error_key}" "${exit_code}"
        fi
        return 0
    fi
    output=$("$@" 2>&1) || exit_code=$?
    if [[ -n "${G_LOG_FILE:-}" && -n "${output}" ]]; then
        printf '%s\n' "${output}" >> "${G_LOG_FILE}"
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

run_silent_apt() {
    local watcher="$1"
    local command="$2"
    local error_key="$3"
    local -a args=()
    local cmd_output="" exit_code=0 attempt=0 max_attempts=30 refreshed=0 line=""
    read -r -a args <<< "${command}"
    sleep 1
    while [[ "${attempt}" -lt "${max_attempts}" ]]; do
        exit_code=0
        if [[ "${watcher}" == "GO" ]]; then
            local fifo="" pid=""
            fifo="$(mktemp -u)"
            mkfifo "${fifo}"
            cmd_output=""
            DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get "${args[@]}" >"${fifo}" 2>&1 </dev/null &
            pid=$!
            while IFS= read -r line; do
                log_emit_go stream "${error_key%.error}.stream" "${line}"
                cmd_output+="${line}"$'\n'
            done < "${fifo}"
            wait "${pid}" || exit_code=$?
            rm -f "${fifo}"
        else
            cmd_output=$(DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get "${args[@]}" </dev/null 2>&1) || exit_code=$?
        fi
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

    [[ ${#steps[@]} -eq 0 ]] && {
        log_error "${INSTALL_WATCHER:-BASH}" "log.no-step-provided"
        return 1
    }

    [[ -z "$dir_install_path" || ! -d "$dir_install_path" ]] && {
        log_error "${INSTALL_WATCHER:-BASH}" "log.dir-install-path-invalid" "$dir_install_path"
        return 1
    }

    local step full_path step_exit step_log
    for step in "${steps[@]}"; do
        full_path="${dir_install_path}/${step}"
        if [[ "${INSTALL_WATCHER:-BASH}" != "GO" ]]; then
            echo "" >&2
            set_color_blue "   $(get_text log.execution-of "${step}")"
            echo "" >&2
        fi

        if [[ ! -f "$full_path" ]]; then
            log_error "${INSTALL_WATCHER:-BASH}" "log.file-not-found" "$full_path"
            exit 1
        fi

        step_exit=0
        step_log=""
        if [[ -n "${G_LOG_DIR:-}" ]]; then
            step_log="${G_LOG_DIR}/steps/$(echo "$step" | tr '/' '-').log"
            mkdir -p "${G_LOG_DIR}/steps"
            set +e
            bash "$full_path" "${INSTALL_WATCHER:-BASH}" "$dir_install_path" "$server_type" 2>&1 | tee -a "$step_log"
            step_exit=${PIPESTATUS[0]}
            set -e
            log_index_append "${step}" "${step_exit}" "${step_log}"
            publish_repo_logs "${G_LOG_DIR}"
        else
            set +e
            bash "$full_path" "${INSTALL_WATCHER:-BASH}" "$dir_install_path" "$server_type"
            step_exit=$?
            set -e
            log_index_append "${step}" "${step_exit}" ""
        fi

        if [[ $step_exit -ne 0 ]]; then
            exit $step_exit
        fi
    done

    return 0
}

# install.json names the steps. The allowed conditions are the flags run.sh already reads.
run_install_plan() {
    local root="$1"
    local plan="$2"
    local profile="${3:-}"
    local category="" id="" kind="" target="" when_var="" when_eq="" envspec="" value="" seen_category=""
    [[ -f "${plan}" ]] || log_error "${INSTALL_WATCHER:-BASH}" "log.file-not-found" "${plan}"
    while IFS=$'\x1f' read -r category id kind target when_var when_eq envspec || [[ -n "${id}" ]]; do
        [[ -n "${id}" ]] || continue
        if [[ "${category}" != "${seen_category}" ]]; then
            seen_category="${category}"
            if [[ "${INSTALL_WATCHER:-BASH}" == "GO" ]]; then
                log_title "${INSTALL_WATCHER}" "${category}"
            else
                set_step_visible "$(get_text "${category}")"
            fi
        fi
        if [[ -n "${when_var}" ]]; then
            case "${when_var}" in
                G_MAIL_ALERTS|G_RCLONE_ALERTS|S_SERVER_TYPE|G_MODE_TEST|S_MODE_DEV) ;;
                *) log_error "${INSTALL_WATCHER:-BASH}" "log.condition.rejected" "${when_var}" ;;
            esac
            value="${!when_var:-}"
            [[ "${value}" == "${when_eq}" ]] || continue
        fi
        if [[ "${kind}" == "path" ]]; then
            if [[ -n "${envspec}" ]]; then
                run_install_step_env "${root}" "${profile}" "${target}" "${envspec}"
            elif [[ -n "${profile}" ]]; then
                run_step "${root}" "${profile}" "${target}"
            else
                run_step "${root}" "${target}"
            fi
        else
            run_install_action "${target}"
        fi
    done < <(python3 - "${plan}" << 'PY'
import json
import sys

allowed = {
    "G_MAIL_ALERTS",
    "G_RCLONE_ALERTS",
    "S_SERVER_TYPE",
    "G_MODE_TEST",
    "S_MODE_DEV",
}
env_allowed = {"G_PURGE_REMOVED_CONFIG_ONLY", "G_REAPPLY_LOCKS"}
plan = json.load(open(sys.argv[1], encoding="utf-8"))
for category in plan["categories"]:
    for step in category["steps"]:
        when = step.get("when") or {}
        var = when.get("var", "")
        eq = str(when.get("eq", ""))
        if var and var not in allowed:
            sys.exit("condition refusée : " + var)
        env = step.get("env") or {}
        for key in env:
            if key not in env_allowed:
                sys.exit("environnement refusé : " + key)
        envspec = ",".join(f"{key}={env[key]}" for key in env)
        if "path" in step:
            kind, target = "path", step["path"]
        else:
            kind, target = "action", step["action"]
        print("\x1f".join([category["id"], step["id"], kind, target, var, eq, envspec]))
PY
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
                G_PURGE_REMOVED_CONFIG_ONLY|G_REAPPLY_LOCKS) ;;
                *) exit 1 ;;
            esac
            printf -v "${key}" '%s' "${val}"
            export "${key}"
        done
        if [[ -n "${profile}" ]]; then
            run_step "${root}" "${profile}" "${step}"
        else
            run_step "${root}" "${step}"
        fi
    ) || exit $?
}
