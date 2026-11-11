#!/usr/bin/env bash
# =============================================================================
# File       : core/host/product.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

product_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${product_dir}/repository.sh"
# shellcheck disable=SC1091
source "${product_dir}/matrix.sh"
# shellcheck disable=SC1091
source "${product_dir}/runtime.sh"
# shellcheck disable=SC1091
source "${product_dir}/collect.sh"
unset product_dir

check_workstation() {
    [[ "${SERVER_TYPE:-}" == "WORKSTATION" || "${PROJECT_SLUG:-}" == "liltress-workstation" ]] && return 0
    [[ -n "${PRODUCT_ROOT:-}" && -f "${PRODUCT_ROOT}/config/global.conf" ]] || return 1
    grep -qE '^(SERVER_TYPE="WORKSTATION"|PROJECT_SLUG="liltress-workstation")$' "${PRODUCT_ROOT}/config/global.conf"
}
