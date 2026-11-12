#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/advice.sh
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


get_alert_tool() {
    local module="${1:-}"
    local log="${2:-}"
    local summary="${3:-}"
    local base
    case "${module}" in
        aide|Aide|AIDE) printf '%s\n' aide; return 0 ;;
        chkrootkit|Chkrootkit|CHKROOTKIT) printf '%s\n' chkrootkit; return 0 ;;
        rkhunter|Rkhunter|RKHUNTER) printf '%s\n' rkhunter; return 0 ;;
    esac
    base="$(basename -- "${log:-}" 2>/dev/null || true)"
    case "${base}" in
        aide-*|*_aide|*_aide.log) printf '%s\n' aide; return 0 ;;
        chkrootkit-*|*_chkrootkit|*_chkrootkit.log) printf '%s\n' chkrootkit; return 0 ;;
        rkhunter-*|*_rkhunter|*_rkhunter.log) printf '%s\n' rkhunter; return 0 ;;
    esac
    case "${summary}" in
        AIDE:*|AIDE\ *) printf '%s\n' aide; return 0 ;;
        chkrootkit*) printf '%s\n' chkrootkit; return 0 ;;
        rkhunter*|mirrors.dat*) printf '%s\n' rkhunter; return 0 ;;
    esac
    return 1
}

render_alert_advice() {
    local tool="${1:-}"
    local log="${2:-}"
    local summary="${3:-}"
    local catalog rendered hold body
    ADVICE=""
    ADVICE_HOLD=0
    catalog="$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")/alert-advice.txt"
    [[ -f "${catalog}" ]] || return 0
    load_text "${LANGUAGE:-en}"
    rendered=""
    rendered="$(
        python3 "$(locate_python_dir)/alert-advice.py" "${tool}" "${log}" "${summary}" "${catalog}"
    )" || rendered=""
    hold="${rendered%%$'\n'*}"
    body="${rendered#*$'\n'}"
    case "${body}" in
        ---) body="" ;;
        ---$'\n'*) body="${body#---$'\n'}" ;;
    esac
    case "${hold}" in
        HOLD=1) ADVICE_HOLD=1 ;;
        *) ADVICE_HOLD=0 ;;
    esac
    ADVICE="${body}"
    return 0
}
