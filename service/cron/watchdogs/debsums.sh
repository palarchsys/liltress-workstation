#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/debsums.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

set -euo pipefail
W_BASE="${W_BASE:-/opt/liltress-workstation}"
# shellcheck disable=SC1091
source "${W_BASE}/cron/bin/common.sh"
LOG_FILE="${LOG_DIR}/debsums-${STAMP}.log"
ALERT_FILE="${ALERT_DIR}/debsums-${STAMP}.txt"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
IGNORE="${HERE}/debsums.ignore"
LOCAL_IGNORE="${W_BASE}/cron/debsums.local.ignore"
if ! command -v debsums >/dev/null; then
    log_pass "$(get_text watchdog.debsums-absent-skip)"
    exit 0
fi
set +e
debsums -s > "${LOG_FILE}" 2>&1
rc=$?
set -e
crashed=0
if [[ "${rc}" -ge 128 ]]; then
    log_alert "$(get_crash_sentence "debsums" "${rc}")"
    crashed=1
fi
python3 - "${LOG_FILE}" "${IGNORE}" "${LOCAL_IGNORE}" "${W_BASE}" << 'PY'
import hashlib
import re
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
base = Path(sys.argv[4])
patterns = []
for ignore_path in sys.argv[2:4]:
    path = Path(ignore_path)
    if not path.is_file():
        continue
    for raw in path.read_text(errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        try:
            patterns.append(re.compile(line))
        except re.error:
            continue

stamp = base / "cron" / "rkhunter-mirrors.sha256"
mirror = Path("/var/lib/rkhunter/db/mirrors.dat")
saved = ""
current = ""
if stamp.is_file() and mirror.is_file():
    parts = stamp.read_text(errors="replace").split()
    saved = parts[0] if parts else ""
    current = hashlib.sha256(mirror.read_bytes()).hexdigest()

def ignored(line):
    if any(p.search(line) for p in patterns):
        return True
    if saved and current == saved and re.search(
        r"^debsums: changed file /var/lib/rkhunter/db/mirrors\.dat \(from rkhunter package\)\s*$",
        line,
    ):
        return True
    if re.search(
        r"^debsums: changed file /usr/lib/\S+/perl-base/unicore/\S+ \(from perl-base package\)\s*$",
        line,
    ):
        return True
    return False

kept = [
    line
    for line in log_path.read_text(errors="replace").splitlines()
    if line.strip() and not ignored(line)
]
log_path.write_text(("\n".join(kept) + "\n") if kept else "")
PY
if [[ "${crashed}" -eq 0 && -s "${LOG_FILE}" ]]; then
    summary="$(repair_debsums_log "${LOG_FILE}")"
    if [[ -n "${summary}" ]]; then
        log_alert "${summary}"
    fi
elif [[ "${crashed}" -eq 0 ]]; then
    log_pass "debsums OK"
fi
exit 0
