#!/usr/bin/env bash
# =============================================================================
# File       : core/host/product.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Open the repository, matrix, runtime, and snapshot scripts.
# -----------------------------------------------------------------------------


product_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${product_directory}/repository.sh"
# shellcheck disable=SC1091
source "${product_directory}/matrix.sh"
# shellcheck disable=SC1091
source "${product_directory}/runtime.sh"
# shellcheck disable=SC1091
source "${product_directory}/collect.sh"

# Return 0 when the desktop marker is present.
check_workstation() {
    [[ "${SERVER_TYPE:-}" == "WORKSTATION" || "${PROJECT_SLUG:-}" == "liltress-workstation" ]] && return 0
    [[ -n "${PRODUCT_ROOT:-}" && -f "${PRODUCT_ROOT}/config/global.conf" ]] || return 1
    grep -qE '^(SERVER_TYPE="WORKSTATION"|PROJECT_SLUG="liltress-workstation")$' "${PRODUCT_ROOT}/config/global.conf"
}
unset product_directory
