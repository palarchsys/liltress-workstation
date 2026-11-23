#!/usr/bin/env bash
# =============================================================================
# File       : system/sysctl/w-sysctl-apply.sh
# Updated at : 2026-11-23
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Apply each sysctl line, skipping a key the kernel does not expose.
# -----------------------------------------------------------------------------


run_w_sysctl_apply_part_01() {
    set -u
    conf="/etc/sysctl.d/99-zzz-liltress-workstation.conf"
    [[ -f "${conf}" ]] || exit 0
}

run_w_sysctl_apply_part_03() {
    run_w_sysctl_apply_part_01 "$@"
}

run_w_sysctl_apply_part_02() {
    exit 0
}

run_w_sysctl_apply_part_04() {
    run_w_sysctl_apply_part_02 "$@"
}

run_w_sysctl_apply_part_03 "$@" "$@"
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

run_w_sysctl_apply_part_04 "$@" "$@"
