#!/usr/bin/env bash
# =============================================================================
# File       : core/boot/bootstrap.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Load one shared engine file from the first directory that has it.
# -----------------------------------------------------------------------------


# The caller owns seen and sourced_core.
source_core_file() {
    local root="$1"
    local name="$2"
    local candidate=""
    [[ -n "${root}" && -d "${root}" ]] || return 0
    candidate="$(cd -- "${root}" && pwd)" || return 0
    if [[ "${seen}" == *"|${candidate}|"* ]]; then
        return 0
    fi
    seen+="${candidate}|"
    if [[ -f "${candidate}/${name}" ]]; then
        # shellcheck disable=SC1090
        source "${candidate}/${name}"
        sourced_core=1
    fi
    return 0
}

source_core() {
    local name="$1"
    local here="" core_root="" root="" seen="|"
    local sourced_core=0
    local -a roots=()
    here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    core_root="$(cd -- "${here}/.." && pwd)"
    roots+=("${core_root}")
    if [[ -n "${PRODUCT_ROOT:-}" ]]; then
        roots+=("${PRODUCT_ROOT}/core" "${PRODUCT_ROOT}/../share/core")
    fi
    if [[ -n "${INSTALL_DIRECTORY:-}" ]]; then
        roots+=("${INSTALL_DIRECTORY}/core" "${INSTALL_DIRECTORY}/../share/core")
    fi
    for root in "${roots[@]}"; do
        source_core_file "${root}" "${name}"
        if [[ "${sourced_core}" -eq 1 ]]; then
            return 0
        fi
    done
    printf 'core/%s not found (PRODUCT_ROOT=%s)\n' "${name}" "${PRODUCT_ROOT:-}" >&2
    exit 1
}
