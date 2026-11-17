#!/usr/bin/env bash
# =============================================================================
# File       : core/boot/lib.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Set the product root and load the shared engine.
# -----------------------------------------------------------------------------


set -euo pipefail

if [[ -z "${PRODUCT_ROOT:-}" ]]; then
    if [[ -n "${INSTALL_DIRECTORY:-}" ]]; then
        PRODUCT_ROOT="${INSTALL_DIRECTORY}"
    else
        PRODUCT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
    fi
fi
export PRODUCT_ROOT

# The caller owns shown_python and reads it after this call.
show_python_directory() {
    local candidate="$1"
    shown_python=0
    [[ -n "${candidate}" && -d "${candidate}" ]] || return 0
    (cd -- "${candidate}" && pwd -P)
    shown_python=1
    return 0
}

# The shared directory is printed as given, without resolving links.
show_share_python() {
    local dir="$1"
    shown_python=0
    if [[ ! -d "${dir}/share/python" ]]; then
        return 0
    fi
    printf '%s\n' "${dir}/share/python"
    shown_python=1
    return 0
}

locate_python_dir() {
    local dir="" hops=0 candidate="" shown_python=0
    for candidate in \
        "${CONFIG_BASE_DIRECTORY:-}/python" \
        "${BASE:-}/python" \
        "${INSTALL_DIRECTORY:-}/python" \
        "${INSTALL_DIRECTORY:-}/../share/python"; do
        show_python_directory "${candidate}"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
    done
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        show_share_python "${dir}"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
        show_python_directory "${dir}/python"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

if [[ -f "${PRODUCT_ROOT}/../share/core/boot/bootstrap.sh" ]]; then
    # shellcheck disable=SC1091
    source "${PRODUCT_ROOT}/../share/core/boot/bootstrap.sh"
elif [[ -f "${PRODUCT_ROOT}/core/boot/bootstrap.sh" ]]; then
    # shellcheck disable=SC1091
    source "${PRODUCT_ROOT}/core/boot/bootstrap.sh"
else
    printf 'bootstrap core not found from %s\n' "${PRODUCT_ROOT}" >&2
    exit 1
fi
source_core log/log.sh
source_core run/exec.sh
source_core host/fs.sh
source_core host/host.sh
source_core host/product.sh
