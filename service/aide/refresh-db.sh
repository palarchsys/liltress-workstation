#!/usr/bin/env bash
# =============================================================================
# File       : service/aide/refresh-db.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

set -euo pipefail
if [[ "${EUID}" -ne 0 ]]; then
    printf "$(get_text log.run-this-command-with-sudo-n)" >&2
    exit 1
fi
if [[ ! -f /etc/aide/aide.conf ]]; then
    printf "$(get_text log.configuration-help-absent-etc-aide-aide-conf-n)" >&2
    exit 1
fi
printf "$(get_text log.calculation-of-the-new-base-help-that-can-take-s)"

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
    printf "$(get_text log.the-new-base-n)"\''a pas été produite (code %s).\n' "${aide_rc}" >&2
    exit 1
fi
if [[ "${aide_rc}" -ne 0 ]]; then
    printf "$(get_text log.help-init-a-returned-the-code-the-base-produced "${aide_rc}")"
fi
printf "$(get_text log.baseline-help-saved-n)"
