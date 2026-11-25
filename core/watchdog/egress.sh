#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/egress.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Build the body of one egress alert.
# -----------------------------------------------------------------------------


source_python_boot() {
    local dir hops
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    hops=0
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        if [[ -f "${dir}/core/boot/python.sh" ]]; then
            # shellcheck disable=SC1090
            source "${dir}/core/boot/python.sh"
            return 0
        fi
        if [[ -f "${dir}/share/core/boot/python.sh" ]]; then
            # shellcheck disable=SC1090
            source "${dir}/share/core/boot/python.sh"
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

source_python_boot

render_egress_body() {
    local kernel="$1"
    local audit="${2:-}"
    EGRESS_AUDIT_FILE="${audit}" python3 "$(locate_python_dir)/egress-body.py" core "${kernel}"
}
