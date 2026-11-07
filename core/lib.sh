#!/usr/bin/env bash
# =============================================================================
# File       : core/lib.sh
# Updated at : 2026-11-07
# Creator    : palarchsys
# =============================================================================

set -euo pipefail

if [[ -z "${PRODUCT_ROOT:-}" ]]; then
    if [[ -n "${INSTALL_DIRECTORY:-}" ]]; then
        PRODUCT_ROOT="${INSTALL_DIRECTORY}"
    else
        PRODUCT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
    fi
fi
export PRODUCT_ROOT

if [[ -f "${PRODUCT_ROOT}/../share/core/bootstrap.sh" ]]; then
    # shellcheck disable=SC1091
    source "${PRODUCT_ROOT}/../share/core/bootstrap.sh"
elif [[ -f "${PRODUCT_ROOT}/core/bootstrap.sh" ]]; then
    # shellcheck disable=SC1091
    source "${PRODUCT_ROOT}/core/bootstrap.sh"
else
    printf 'bootstrap core not found from %s\n' "${PRODUCT_ROOT}" >&2
    exit 1
fi
source_core log.sh
source_core exec.sh
source_core fs.sh
source_core host.sh
source_core product.sh
