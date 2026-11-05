#!/usr/bin/env bash
# =============================================================================
# File       : core/bootstrap.sh
# Updated at : 2026-11-05
# Creator    : palarchsys
# =============================================================================

source_core() {
    local name="$1"
    local candidate
    local -a candidates=(
        "${PRODUCT_ROOT}/../share/core/${name}"
        "${PRODUCT_ROOT}/core/${name}"
    )
    for candidate in "${candidates[@]}"; do
        if [[ -f "${candidate}" ]]; then
            # shellcheck disable=SC1090
            source "${candidate}"
            return 0
        fi
    done
    printf 'core/%s not found (PRODUCT_ROOT=%s)\n' "${name}" "${PRODUCT_ROOT}" >&2
    exit 1
}
