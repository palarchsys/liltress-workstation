#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/debsums.sh
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


set_rkhunter_note() {
    local base
    base="$(get_product_base)"
    NOTE="$(get_text alert.note.rkhunter)"
    NOTE_CMD="sudo bash ${base}/bin/rkhunter-refresh-db.sh"
}

reset_debsums_log() {
    local log="$1"
    local summary=""
    [[ -n "${log}" && -s "${log}" ]] || return 0
    summary="$(
        python3 "$(locate_python_dir)/debsums-reset.py" "${log}" || true
    )"
    printf '%s' "${summary}"
}
