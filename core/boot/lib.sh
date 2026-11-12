#!/usr/bin/env bash
# =============================================================================
# File       : core/boot/lib.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

set -euo pipefail

if [[ -z "${PRODUCT_ROOT:-}" ]]; then
    if [[ -n "${INSTALL_DIRECTORY:-}" ]]; then
        PRODUCT_ROOT="${INSTALL_DIRECTORY}"
    else
        PRODUCT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
    fi
fi
export PRODUCT_ROOT

locate_python_dir() {
    local dir hops=0 candidate
    for candidate in \
        "${CONFIG_BASE_DIRECTORY:-}/python" \
        "${BASE:-}/python" \
        "${INSTALL_DIRECTORY:-}/python" \
        "${INSTALL_DIRECTORY:-}/../share/python"
    do
        if [[ -n "${candidate}" && -d "${candidate}" ]]; then
            (cd -- "${candidate}" && pwd -P)
            return 0
        fi
    done
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        if [[ -d "${dir}/share/python" ]]; then
            printf '%s\n' "${dir}/share/python"
            return 0
        fi
        if [[ -d "${dir}/python" ]]; then
            (cd -- "${dir}/python" && pwd -P)
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

install_python_runtime() {
    local src="" dest="" candidate
    dest="${CONFIG_BASE_DIRECTORY:?}/python"
    for candidate in \
        "${INSTALL_DIRECTORY:-}/python" \
        "${INSTALL_DIRECTORY:-}/../share/python" \
        "${DIR_SCRIPT_PATH:-}/../../python" \
        "${DIR_SCRIPT_PATH:-}/../../../share/python"
    do
        if [[ -n "${candidate}" && -d "${candidate}" ]]; then
            src="$(cd -- "${candidate}" && pwd -P)"
            break
        fi
    done
    if [[ -z "${src}" ]]; then
        log_error "${INSTALL_WATCHER:-BASH}" "configure.core-watchdog-sh-not-found" "python"
    fi
    mkdir -p -- "${dest}"
    cp -a --dereference --remove-destination "${src}/." "${dest}/"
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
