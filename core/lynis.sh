#!/usr/bin/env bash
# =============================================================================
# File       : core/lynis.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

set -euo pipefail

root="${1:-}"
auditor="${2:-}"
if [[ -z "${root}" || ! -d "${root}" ]]; then
    printf "$(get_text log.usage-lynis-sh-root-listener-n)" >&2
    exit 2
fi
if [[ -z "${auditor}" && -f "${root}/config/global.conf" ]]; then
    auditor="$(awk -F= '/^W_PROJECT_SLUG=/{gsub(/["'\'']/, "", $2); gsub(/[[:space:]]/, "", $2); print $2; exit}' "${root}/config/global.conf")"
fi
auditor="${auditor:-liltress}"
if [[ "${EUID}" -ne 0 ]]; then
    printf "$(get_text log.lynis-audit-system-requires-root-sudo-n)" >&2
    exit 1
fi

stamp="$(date +%Y%m%d-%H%M%S)"
out="${root}/log/lynis-${stamp}"
mkdir -p "${out}"
lynis audit system --quick --no-colors --auditor "${auditor}" | tee "${out}/lynis-audit.txt"
cp -a /var/log/lynis.log "${out}/lynis.log" 2>/dev/null || true
cp -a /var/log/lynis-report.dat "${out}/lynis-report.dat" 2>/dev/null || true
chmod 640 /var/log/lynis.log /var/log/lynis-report.dat 2>/dev/null || true
{
    echo "$(get_text log.hostname)"; hostname; uname -a
    echo "$(get_text log.score)"; grep -E "hardening_index|lynis_tests_done" /var/log/lynis-report.dat || true
    echo "$(get_text log.warnings)"; grep -E "^warning\[\]=" /var/log/lynis-report.dat || true
    echo "$(get_text log.suggestions)"; grep -E "^suggestion\[\]=" /var/log/lynis-report.dat || true
} > "${out}/summary.txt"
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/log.sh"
printf 'Rapport : %s\n' "$(show_path "${out}")"
