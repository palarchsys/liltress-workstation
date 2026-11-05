#!/usr/bin/env bash
# =============================================================================
# File       : core/launch.sh
# Updated at : 2026-11-05
# Creator    : palarchsys
# =============================================================================

load_launch_text() {
    local root="$1"
    local launch_here="" launch_candidate=""
    if [[ -z "${PRODUCT_ROOT:-}" ]]; then
        PRODUCT_ROOT="${root}"
        export PRODUCT_ROOT
    fi
    if ! declare -F get_text >/dev/null 2>&1; then
        launch_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
        for launch_candidate in \
            "${launch_here}/log.sh" \
            "${root}/core/log.sh" \
            "${root}/src/core/log.sh"
        do
            if [[ -n "${launch_candidate}" && -f "${launch_candidate}" ]]; then
                # shellcheck disable=SC1090
                source "${launch_candidate}"
                break
            fi
        done
    fi
    if declare -F read_language_file >/dev/null 2>&1 \
        && [[ -f "${root}/config/global.conf" ]]; then
        read_language_file "${root}/config/global.conf"
    elif declare -F load_text >/dev/null 2>&1; then
        load_text "${LANGUAGE:-en}"
    fi
}

run_launch() {
    local root="$1"
    local cmd="${2:-help}"
    shift 2 || true
    load_launch_text "${root}"
    case "${cmd}" in
        configure)
            exec bash "${root}/script/configure.sh" "$@"
            ;;
        check)
            exec bash "${root}/script/configure.sh" --check "$@"
            ;;
        run)
            exec bash "${root}/script/run.sh" "$@"
            ;;
        lynis)
            exec bash "${root}/core/lynis.sh" "${root}" "$@"
            ;;
        logs)
            exec bash "${root}/system/collect-logs.sh" "$@"
            ;;
        vpn)
            if [[ -f "${root}/service/vpn/cli.sh" ]]; then
                exec bash "${root}/service/vpn/cli.sh" "$@"
            fi
            printf '%s\n' "$(get_text launch.unknown-command "${cmd}")" >&2
            printf '%s\n' "$(get_text launch.usage-liltress-help "${root}")" >&2
            exit 2
            ;;
        help|-h|--help)
            printf '%s\n' "$(get_text launch.usage "${root}")"
            if [[ -f "${root}/verify/workstation.sh" || -f "${root}/verify/matrix.sh" ]]; then
                extra="$(get_text launch.usage.extra)"
                if [[ "${extra}" != "launch.usage.extra" ]]; then
                    printf '\n%s\n' "${extra}"
                fi
            fi
            ;;
        *)
            printf '%s\n' "$(get_text launch.unknown-command "${cmd}")" >&2
            printf '%s\n' "$(get_text launch.usage-liltress-help "${root}")" >&2
            exit 2
            ;;
    esac
}
