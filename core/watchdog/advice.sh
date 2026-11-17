#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/advice.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Turn one finding into the advice block of a mail.
# -----------------------------------------------------------------------------


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

# The tool name is printed when the module name is recognized.
show_alert_module() {
    case "$1" in
        aide | Aide | AIDE)
            printf '%s\n' aide
            return 0
            ;;
        chkrootkit | Chkrootkit | CHKROOTKIT)
            printf '%s\n' chkrootkit
            return 0
            ;;
        rkhunter | Rkhunter | RKHUNTER)
            printf '%s\n' rkhunter
            return 0
            ;;
    esac
    return 1
}

# The tool name is printed when the journal name is recognized.
show_alert_basename() {
    case "$1" in
        aide-* | *_aide | *_aide.log)
            printf '%s\n' aide
            return 0
            ;;
        chkrootkit-* | *_chkrootkit | *_chkrootkit.log)
            printf '%s\n' chkrootkit
            return 0
            ;;
        rkhunter-* | *_rkhunter | *_rkhunter.log)
            printf '%s\n' rkhunter
            return 0
            ;;
    esac
    return 1
}

# The tool name is printed when the summary line is recognized.
show_alert_summary() {
    case "$1" in
        AIDE:* | AIDE\ *)
            printf '%s\n' aide
            return 0
            ;;
        chkrootkit*)
            printf '%s\n' chkrootkit
            return 0
            ;;
        rkhunter* | mirrors.dat*)
            printf '%s\n' rkhunter
            return 0
            ;;
    esac
    return 1
}

get_alert_tool() {
    local module="${1:-}"
    local log="${2:-}"
    local summary="${3:-}"
    local base=""
    if show_alert_module "${module}"; then
        return 0
    fi
    base="$(basename -- "${log:-}" 2>/dev/null || true)"
    if show_alert_basename "${base}"; then
        return 0
    fi
    show_alert_summary "${summary}"
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
