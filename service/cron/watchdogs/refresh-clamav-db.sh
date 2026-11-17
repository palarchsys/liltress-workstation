#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/refresh-clamav-db.sh
# Updated at : 2026-11-17
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Run one extra freshclam pass beside the daemon.
# Note       : A download already in progress leaves the daemon alone.
# Note       : A lock held by the sleeping daemon is a quiet success.
# -----------------------------------------------------------------------------


freshclam_writing() {
    local path=""
    [[ -d /var/lib/clamav ]] || return 1
    for path in /var/lib/clamav/*.tmp /var/lib/clamav/*.cvd.part /var/lib/clamav/*.cld.part; do
        [[ -e "${path}" ]] || continue
        return 0
    done
    return 1
}

freshclam_locked() {
    local text="$1"
    grep -Eqi 'already running|locked|resource temporarily unavailable|another freshclam' <<<"${text}"
}

set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/common.sh"
if ! command -v freshclam >/dev/null 2>&1; then
    exit 0
fi
if freshclam_writing; then
    exit 0
fi
out="$(mktemp)"
rc=0
freshclam --quiet >"${out}" 2>&1 || rc=$?
if [[ "${rc}" -eq 0 ]] || freshclam_locked "$(cat "${out}")"; then
    rm -f "${out}"
    exit 0
fi
rm -f "${out}"
exit "${rc}"
