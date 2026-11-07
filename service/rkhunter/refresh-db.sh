#!/usr/bin/env bash
# =============================================================================
# File       : service/rkhunter/refresh-db.sh
# Updated at : 2026-11-06
# Creator    : palarchsys
# =============================================================================

set -euo pipefail
_text_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
_text_hops=0
while [[ "${_text_hops}" -lt 8 && "${_text_dir}" != "/" ]]; do
    if [[ -f "${_text_dir}/text-load.sh" ]]; then
        # shellcheck disable=SC1090
        source "${_text_dir}/text-load.sh"
        break
    fi
    if [[ -f "${_text_dir}/share/core/text-load.sh" ]]; then
        # shellcheck disable=SC1090
        source "${_text_dir}/share/core/text-load.sh"
        break
    fi
    if [[ -f "${_text_dir}/core/text-load.sh" ]]; then
        # shellcheck disable=SC1090
        source "${_text_dir}/core/text-load.sh"
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
if [[ "${EUID}" -ne 0 ]]; then
    printf "$(get_text log.run-this-command-with-sudo-n)" >&2
    exit 1
fi
if ! command -v rkhunter >/dev/null 2>&1; then
    printf "$(get_text log.rkhunter-is-absent-n)" >&2
    exit 1
fi
printf "$(get_text log.calculation-of-the-properties-baseline-rkhunter)"
set +e
rkhunter --propupd --nocolors
rc=$?
set -e
if [[ "${rc}" -ne 0 ]]; then
    printf "$(get_text log.rkhunter-propupd-a-returned-the-code "${rc}")" >&2
    exit 1
fi
printf "$(get_text log.properties-baseline-rkhunter-saved-n)"
