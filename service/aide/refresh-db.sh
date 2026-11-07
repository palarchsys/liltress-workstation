#!/usr/bin/env bash
# =============================================================================
# File       : service/aide/refresh-db.sh
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
if [[ ! -f /etc/aide/aide.conf ]]; then
    printf "$(get_text log.configuration-help-absent-etc-aide-aide-conf-n)" >&2
    exit 1
fi
printf '%s\n' "$(get_text log.the-calculation-of-the-fingerprints-can-take-sev)"

rm -f /var/lib/aide/aide.db.new /var/lib/aide/aide.db.new.gz
set +e
aide --config=/etc/aide/aide.conf --init
aide_rc=$?
set -e
if [[ -f /var/lib/aide/aide.db.new.gz ]]; then
    mv -f /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
    ln -sfn /var/lib/aide/aide.db.gz /var/lib/aide/aide.db
elif [[ -f /var/lib/aide/aide.db.new ]]; then
    mv -f /var/lib/aide/aide.db.new /var/lib/aide/aide.db
else
    printf '%s\n' "$(get_text log.base-help-not-generated-help-db-new-not-found-de "${aide_rc}")" >&2
    exit 1
fi
if [[ "${aide_rc}" -ne 0 ]]; then
    printf '%s\n' "$(get_text log.help-init-a-returned-an-error-detail "${aide_rc}")"
fi
printf '%s\n' "$(get_text log.baseline-help-saved)"
