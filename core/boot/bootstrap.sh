#!/usr/bin/env bash
# =============================================================================
# File       : core/boot/bootstrap.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

source_core() {
    local name="$1"
    local here="" core_root="" root="" candidate="" seen="|"
    local -a roots=()
    here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    core_root="$(cd -- "${here}/.." && pwd)"
    roots+=("${core_root}")
    if [[ -n "${PRODUCT_ROOT:-}" ]]; then
        roots+=("${PRODUCT_ROOT}/core" "${PRODUCT_ROOT}/src/core" "${PRODUCT_ROOT}/../share/core")
    fi
    if [[ -n "${INSTALL_DIRECTORY:-}" ]]; then
        roots+=("${INSTALL_DIRECTORY}/core" "${INSTALL_DIRECTORY}/src/core" "${INSTALL_DIRECTORY}/../share/core")
    fi
    for root in "${roots[@]}"; do
        [[ -n "${root}" && -d "${root}" ]] || continue
        candidate="$(cd -- "${root}" && pwd)" || continue
        [[ "${seen}" == *"|${candidate}|"* ]] && continue
        seen+="${candidate}|"
        if [[ -f "${candidate}/${name}" ]]; then
            # shellcheck disable=SC1090
            source "${candidate}/${name}"
            return 0
        fi
    done
    printf 'core/%s not found (PRODUCT_ROOT=%s)\n' "${name}" "${PRODUCT_ROOT:-}" >&2
    exit 1
}
