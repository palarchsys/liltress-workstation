#!/usr/bin/env bash
# =============================================================================
# File       : script/scan-skip.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================


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

set -euo pipefail
_text_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
_text_hops=0
while [[ "${_text_hops}" -lt 8 && "${_text_dir}" != "/" ]]; do
    if [[ -f "${_text_dir}/text-load.sh" ]]; then
        # shellcheck disable=SC1090
        source "${_text_dir}/text-load.sh"
        break
    fi
    if [[ -f "${_text_dir}/share/core/text/text-load.sh" ]]; then
        # shellcheck disable=SC1090
        source "${_text_dir}/share/core/text/text-load.sh"
        break
    fi
    if [[ -f "${_text_dir}/core/text/text-load.sh" ]]; then
        # shellcheck disable=SC1090
        source "${_text_dir}/core/text/text-load.sh"
        break
    fi
    _text_dir="$(dirname -- "${_text_dir}")"
    _text_hops=$((_text_hops + 1))
done
unset _text_dir _text_hops
if ! declare -F load_installed_text >/dev/null 2>&1; then
    printf '%s\n' "get_text absent" >&2
    exit 1
fi
load_installed_text
BASE="${BASE:-/opt/liltress-workstation}"
# shellcheck disable=SC1091
source "${BASE}/cron/bin/scan-skip-lib.sh"

show_usage() {
    printf "$(get_text log.usage-sudo-bash-bin-scan-skip-sh-list "${BASE}")" >&2
    printf "$(get_text log.sudo-bash-bin-scan-skip-sh-add-chemin "${BASE}")" >&2
    printf "$(get_text log.sudo-bash-bin-scan-skip-sh-del-chemin "${BASE}")" >&2
}

if [[ "${EUID}" -ne 0 ]]; then
    printf "$(get_text log.run-this-command-with-sudo-n)" >&2
    exit 1
fi

action="${1:-}"
case "${action}" in
    list|add|del) ;;
    *)
        show_usage
        exit 1
        ;;
esac

if [[ ! -f "${SCAN_SKIP_FILE}" ]]; then
    printf "$(get_text log.file-absent "${SCAN_SKIP_FILE}")" >&2
    exit 1
fi

if [[ "${action}" == "list" ]]; then
    collect_scan_skip_path
    if [[ ${#SCAN_SKIP_VALID[@]} -gt 0 ]]; then
        printf '%s\n' "${SCAN_SKIP_VALID[@]}"
    fi
    if [[ ${#SCAN_SKIP_BAD[@]} -gt 0 ]]; then
        for line in "${SCAN_SKIP_BAD[@]}"; do
            printf "$(get_text log.path-denied "${line}")" >&2
        done
    fi
    exit 0
fi

if [[ $# -ne 2 ]]; then
    show_usage
    exit 1
fi

if ! norm="$(check_scan_skip_path "$2")"; then
    printf "$(get_text log.path-denied "$2")" >&2
    exit 1
fi

collect_scan_skip_path
found=0
if [[ ${#SCAN_SKIP_VALID[@]} -gt 0 ]]; then
    for path in "${SCAN_SKIP_VALID[@]}"; do
        [[ "${path}" == "${norm}" ]] && found=1
    done
fi

if [[ "${action}" == "add" ]]; then
    if [[ "${found}" -eq 1 ]]; then
        printf "$(get_text log.this-path-is-already-excluded-s-n)" "${norm}"
        exit 0
    fi
    if [[ -s "${SCAN_SKIP_FILE}" ]] && [[ "$(tail -c1 "${SCAN_SKIP_FILE}" | wc -l)" -eq 0 ]]; then
        printf "$(get_text log.n)" >> "${SCAN_SKIP_FILE}"
    fi
    printf '%s\n' "${norm}" >> "${SCAN_SKIP_FILE}"
    printf "$(get_text log.path-added "${norm}")"
else
    if [[ "${found}" -eq 0 ]]; then
        printf '%s\n' "$(get_text log.path-absent-of-the-list "${norm}")" >&2
        exit 1
    fi
    python3 "$(locate_python_dir)/scan-skip-path.py" edit "${SCAN_SKIP_FILE}" "${norm}"
    printf "$(get_text log.path-removed "${norm}")"
fi

bash "${BASE}/cron/bin/apply-scan-skip.sh"
exit 0
