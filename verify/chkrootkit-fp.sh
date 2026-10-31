#!/usr/bin/env bash
# =============================================================================
# File       : verify/chkrootkit-fp.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

set +e

if [[ "${EUID}" -ne 0 ]]; then
    echo "$(get_text log.run-this-script-with-sudo-sudo-bash-verify-chkro)" >&2
    exit 1
fi

if ! command -v chkrootkit >/dev/null 2>&1; then
    echo "$(get_text log.chkrootkit-is-absent)" >&2
    exit 1
fi

log_dir="/var/log/liltress-workstation"
mkdir -p "${log_dir}"
stamp="$(date +%Y%m%d-%H%M%S)"
log_file="${log_dir}/chkrootkit-fp-${stamp}.log"
version="$(chkrootkit -V 2>&1 | head -5)"

{
    echo "$(get_text log.liltress-workstation-report-chkrootkit-false-pos)"
    echo "$(get_text log.date-2 "$(date -Iseconds)")"
    echo "$(get_text log.host "$(hostname)")"
    echo "$(get_text log.start "$(uptime -s 2>/dev/null || who -b)")"
    echo "$(get_text log.command-chkrootkit-q)"
    echo "$(get_text log.version)"
    printf '%s\n' "${version}"
    echo
    echo "$(get_text log.output)"
} | tee "${log_file}"

echo "$(get_text log.the-check-can-take-several-minutes)"
chkrootkit -q >> "${log_file}" 2>&1
rc=$?

if [[ "$(tail -n 1 "${log_file}")" == "===== SORTIE =====" ]]; then
    {
        echo "$(get_text log.no-line-chkrootkit-q-is-remained-silencieux)"
    } | tee -a "${log_file}"
fi

{
    echo
    echo "$(get_text log.end)"
    echo "$(get_text log.code-of-return "${rc}")"
    echo "$(get_text log.journal "${log_file}")"
    echo "$(get_text log.copy-all-this-output-for-make-up-the-list-of-exc)"
} | tee -a "${log_file}"

exit 0
