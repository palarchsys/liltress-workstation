#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/egress.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================


locate_python_dir() {
    local dir hops=0
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        if [[ -d "${dir}/share/python" ]]; then
            printf '%s\n' "${dir}/share/python"
            return 0
        fi
        if [[ -d "${dir}/python" ]]; then
            printf '%s\n' "${dir}/python"
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}


render_egress_body() {
    local kernel="$1"
    local audit="${2:-}"
    EGRESS_AUDIT_FILE="${audit}" python3 "$(locate_python_dir)/egress-body.py" core "${kernel}"
}
