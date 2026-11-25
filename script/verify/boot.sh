#!/usr/bin/env bash
# =============================================================================
# File       : script/verify/boot.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Open the text catalog, demand root, and hand off to the boot probe.
# -----------------------------------------------------------------------------


_text_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
_text_hops=0
while [[ "${_text_hops}" -lt 8 && "${_text_directory}" != "/" ]]; do
    if [[ -f "${_text_directory}/text-load.sh" ]]; then
        # shellcheck disable=SC1090
        source "${_text_directory}/text-load.sh"
        break
    fi
    if [[ -f "${_text_directory}/share/core/text/text-load.sh" ]]; then
        # shellcheck disable=SC1090
        source "${_text_directory}/share/core/text/text-load.sh"
        break
    fi
    if [[ -f "${_text_directory}/core/text/text-load.sh" ]]; then
        # shellcheck disable=SC1090
        source "${_text_directory}/core/text/text-load.sh"
        break
    fi
    _text_directory="$(dirname -- "${_text_directory}")"
    _text_hops=$((_text_hops + 1))
done
unset _text_directory _text_hops
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
