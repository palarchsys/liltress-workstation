#!/usr/bin/env bash
# =============================================================================
# File       : script/verify/boot.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

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
if [[ "${EUID}" -ne 0 ]]; then
    printf "$(get_text log.run-this-command-with-sudo-n)" >&2
    exit 1
fi

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${here}/../boot-check.sh"
