#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/limit.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Start one command with a low processor and disk priority.
# Note       : The command status is kept.
# -----------------------------------------------------------------------------


get_cpu_quota_percent() {
    local limit="${WATCHDOG_CPU_LIMIT:-50}"
    local n=1
    if [[ ! "${limit}" =~ ^[0-9]+$ ]]; then
        limit=50
    fi
    if command -v nproc >/dev/null 2>&1; then
        n="$(nproc 2>/dev/null)" || n=1
    fi
    if [[ ! "${n}" =~ ^[0-9]+$ ]] || [[ "${n}" -lt 1 ]]; then
        n=1
    fi
    printf '%s\n' "$((limit * n))"
}

# The caller owns status. A low priority is used when the tools exist.
run_limited_nice() {
    local pid=0 lim=0
    local -a cmd=()
    if command -v nice >/dev/null 2>&1; then
        cmd+=(nice -n "${WATCHDOG_LIMIT_NICE:-19}")
    fi
    if command -v ionice >/dev/null 2>&1; then
        cmd+=(ionice -c "${WATCHDOG_LIMIT_IO_NICE:-3}")
    fi
    if [[ "${#cmd[@]}" -eq 0 ]]; then
        "$@" &
    else
        "${cmd[@]}" "$@" &
    fi
    pid=$!
    if command -v cpulimit >/dev/null 2>&1; then
        cpulimit -p "${pid}" -l "$(get_cpu_quota_percent)" -z >/dev/null 2>&1 &
        lim=$!
    fi
    wait "${pid}"
    status=$?
    if [[ "${lim}" -ne 0 ]]; then
        kill "${lim}" 2>/dev/null
        wait "${lim}" 2>/dev/null
    fi
    return "${status}"
}

run_limited() {
    local status=0 errexit=0
    case $- in
        *e*) errexit=1 ;;
    esac
    set +e
    if [[ "${LIMIT_WRAP:-1}" == "0" ]]; then
        "$@"
        status=$?
    else
        run_limited_nice "$@"
        status=$?
    fi
    if [[ "${errexit}" -eq 1 ]]; then
        set -e
    fi
    return "${status}"
}
