#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/chkrootkit.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

set -euo pipefail
W_BASE="${W_BASE:-/opt/liltress-workstation}"
# shellcheck disable=SC1091
source "${W_BASE}/cron/bin/common.sh"
LOG_FILE="${LOG_DIR}/chkrootkit-${STAMP}.log"
ALERT_FILE="${ALERT_DIR}/chkrootkit-${STAMP}.txt"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${W_BASE}/src/core/fs.sh" ]]; then
    # shellcheck disable=SC1091
    source "${W_BASE}/src/core/fs.sh"
elif [[ -f "${HERE}/../../../core/fs.sh" ]]; then
    # shellcheck disable=SC1091
    source "${HERE}/../../../core/fs.sh"
fi
IGNORE=""
if declare -F locate_config_file >/dev/null 2>&1; then
    IGNORE="$(locate_config_file chkrootkit/patterns.ignore || true)"
fi
if [[ ! -f "${IGNORE}" && -f "${HERE}/../../../config/chkrootkit/patterns.ignore" ]]; then
    IGNORE="${HERE}/../../../config/chkrootkit/patterns.ignore"
fi
if [[ ! -f "${IGNORE}" && -f "${HERE}/chkrootkit.ignore" ]]; then
    IGNORE="${HERE}/chkrootkit.ignore"
fi
if [[ ! -f "${IGNORE}" ]]; then
    IGNORE="${W_BASE}/src/config/chkrootkit/patterns.ignore"
fi

LOCAL_IGNORE="${W_BASE}/cron/chkrootkit.local.ignore"
if ! command -v chkrootkit >/dev/null; then
    log_pass "$(get_text watchdog.chkrootkit-absent-skip)"
    exit 0
fi
set +e
chkrootkit -q -s 'NetworkManager|wpa_supplicant|systemd-networkd' > "${LOG_FILE}" 2>&1
rc=$?
set -e
crashed=0
if [[ "${rc}" -ge 128 ]]; then
    log_alert "$(get_crash_sentence "chkrootkit" "${rc}")"
    crashed=1
fi
if [[ -f "${IGNORE}" || -f "${LOCAL_IGNORE}" ]]; then
    python3 - "${LOG_FILE}" "${IGNORE}" "${LOCAL_IGNORE}" << 'PY'
import re
import sys
from pathlib import Path

log_path = sys.argv[1]
patterns = []
for ignore_path in sys.argv[2:]:
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

def ignored(line):
    return any(p.search(line) for p in patterns)

kept = [line for line in Path(log_path).read_text(errors="replace").splitlines() if line.strip() and not ignored(line)]
headers = {
    "WARNING: The following suspicious files and directories were found:",
    "WARNING: Possible Linux BPFDoor Malware installed:",
    "WARNING: output from chkwtmp:",
    "WARNING: Output from ifpromisc:",
}
out = []
i = 0
while i < len(kept):
    line = kept[i]
    if line in headers:
        body = []
        j = i + 1
        while j < len(kept) and kept[j] not in headers and not kept[j].startswith("Checking "):
            body.append(kept[j])
            j += 1
        if body:
            out.append(line)
            out.extend(body)
        i = j
        continue
    out.append(line)
    i += 1
Path(log_path).write_text(("\n".join(out) + "\n") if out else "")
PY
fi
G_CONFIRMED_COUNT=0
confirmed_tmp="$(mktemp)"
quarantine_confirmed_log chkrootkit "${LOG_FILE}" systemd sshd unbound fail2ban gamescope > "${confirmed_tmp}" || true
if [[ -s "${confirmed_tmp}" ]]; then
    cat "${confirmed_tmp}" >> "${LOG_FILE}"
fi
rm -f "${confirmed_tmp}"
if [[ -s "${LOG_FILE}" ]]; then
    if [[ "${G_CONFIRMED_COUNT:-0}" -eq 0 ]]; then
        W_CHKROOTKIT_IGNORE=1 \
            log_alert "$(get_text watchdog.chkrootkit-a-produced-a-output-see "${LOG_FILE}")"
    else
        log_alert "$(get_text watchdog.chkrootkit-a-produced-a-output-see "${LOG_FILE}")"
    fi
elif [[ "${crashed}" -eq 0 ]]; then
    log_pass "$(get_text watchdog.chkrootkit-silencieux-ok)"
fi
exit 0
