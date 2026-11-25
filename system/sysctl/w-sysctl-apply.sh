#!/usr/bin/env bash
# =============================================================================
# File       : system/sysctl/w-sysctl-apply.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Apply each sysctl line, skipping a key the kernel does not expose.
# -----------------------------------------------------------------------------


sysctl_w_sysctl_apply_01_run_01_run() {
    set -u
    conf="/etc/sysctl.d/99-zzz-liltress-workstation.conf"
    [[ -f "${conf}" ]] || exit 0
}

sysctl_w_sysctl_apply_01_run_03_run() {
    sysctl_w_sysctl_apply_01_run_01_run "$@"
}

sysctl_w_sysctl_apply_01_run_02_run() {
    exit 0
}

sysctl_w_sysctl_apply_01_run_04_run() {
    sysctl_w_sysctl_apply_01_run_02_run "$@"
}

sysctl_w_sysctl_apply_01_run_03_run "$@" "$@"
while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "${line}" ]] && continue
    [[ "${line}" == *=* ]] || continue
    key="${line%%=*}"
    key="${key%"${key##*[![:space:]]}"}"
    val="${line#*=}"
    val="${val#"${val%%[![:space:]]*}"}"

    proc="/proc/sys/${key//.//}"
    if [[ ! -e "${proc}" ]]; then
        printf "$(get_text log.ignored-absent "${key}")" >&2
        continue
    fi
    err="$(sysctl -w "${key}=${val}" 2>&1)" && continue
    current="$(sysctl -n "${key}" 2>/dev/null || true)"
    if [[ "${current}" == "${val}" ]]; then
        continue
    fi

    printf "$(get_text log.ignored "${err}")" >&2
done <"${conf}"

sysctl_w_sysctl_apply_01_run_04_run "$@" "$@"
