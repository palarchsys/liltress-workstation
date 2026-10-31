#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/apply-scan-skip.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================
# -----------------------------------------------------------------------------
# Note       : Fixed excludes from onaccess.conf join the same block.
# Note       : The temporary file is created under /run/liltress-workstation.
# Note       : Each OnAccessExcludePath value matches that directory only.
# -----------------------------------------------------------------------------

set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/scan-skip-lib.sh"

restart_scan_skip_service() {
    local unit
    if systemctl cat clamav-daemon.service >/dev/null 2>&1; then
        systemctl restart clamav-daemon
    fi
    for unit in clamav-clamonacc.service clamonacc.service; do
        if systemctl cat "${unit}" >/dev/null 2>&1; then
            systemctl restart "${unit}"
            return 0
        fi
    done
}

if [[ -n "${W_SCAN_SKIP_HOME:-}" ]]; then
    ensure_scan_skip_file "${W_SCAN_SKIP_HOME}"
fi

load_onaccess_exclude() {
    local candidate found=""
    W_ONACCESS_FIXED_EXCLUDE="${W_ONACCESS_FIXED_EXCLUDE:-/var/lib/snapd /snap /var/lib/clamav/quarantine /var/lib/clamav/tmp /opt/liltress-workstation /var/log}"
    for candidate in \
        "${G_INSTALL_DIRECTORY:-}/config/clamav/onaccess.conf" \
        "${W_BASE}/src/config/clamav/onaccess.conf" \
        "/opt/liltress-workstation/src/config/clamav/onaccess.conf"
    do
        [[ -f "${candidate}" ]] || continue
        found="${candidate}"
        break
    done
    if [[ -n "${found}" ]]; then
        # shellcheck disable=SC1090
        source "${found}"
    fi
    W_ONACCESS_FIXED=()
    local path
    # shellcheck disable=SC2086
    for path in ${W_ONACCESS_FIXED_EXCLUDE}; do
        [[ -n "${path}" ]] || continue
        W_ONACCESS_FIXED+=("${path}")
    done
    if [[ -n "${W_BASE:-}" ]]; then
        W_ONACCESS_FIXED+=("${W_BASE}")
    fi
    local kept=()
    for path in "${W_ONACCESS_FIXED[@]+"${W_ONACCESS_FIXED[@]}"}"; do
        [[ "${path}" == "${W_BASE}/src" ]] && continue
        kept+=("${path}")
    done
    W_ONACCESS_FIXED=("${kept[@]+"${kept[@]}"}")
}

load_onaccess_exclude
collect_scan_skip_path
if [[ ${#W_SCAN_SKIP_BAD[@]} -gt 0 ]]; then
    install -d -m 750 "${W_BASE}/cron/security_logs"
    for line in "${W_SCAN_SKIP_BAD[@]}"; do
        printf "$(get_text watchdog.s-path-denied-s-n)" "$(date -Iseconds)" "${line}" | tee -a "${W_BASE}/cron/security_logs/scan-skip.log"
    done
fi

conf="/etc/clamav/clamd.conf"
if [[ -f "${conf}" ]]; then
    install -d -m 755 /run/liltress-workstation
    tmp="$(mktemp -p /run/liltress-workstation)"
    trap 'rm -f "${tmp}"' EXIT
    changed="$(python3 - "${conf}" "${tmp}" "${#W_ONACCESS_FIXED[@]}" "${W_ONACCESS_FIXED[@]}" "${W_SCAN_SKIP_VALID[@]}" << 'PY'
import re
import sys
from pathlib import Path

conf = Path(sys.argv[1])
dest = Path(sys.argv[2])
count = int(sys.argv[3])
fixed = sys.argv[4:4 + count]
paths = sys.argv[4 + count:]
seen = []
for path in list(fixed) + list(paths):
    if path and path not in seen:
        seen.append(path)
paths = seen
text = conf.read_text(errors="replace")
begin = "# BEGIN Liltress Workstation scan-skip"
end = "# END Liltress Workstation scan-skip"
old_begin = "# BEGIN High-Fortress User scan-skip"
old_end = "# END High-Fortress User scan-skip"
out = []
skipping = False
for line in text.splitlines():
    stripped = line.strip()
    if stripped in (begin, old_begin):
        skipping = True
        continue
    if skipping:
        if stripped in (end, old_end):
            skipping = False
        continue
    if line.startswith("OnAccessExcludePath "):
        continue
    out.append(line)
while out and out[-1] == "":
    out.pop()
block = [begin]
for path in paths:
    block.append("OnAccessExcludePath ^" + re.escape(path) + "$")
block.append(end)
out.append("")
out.extend(block)
new = "\n".join(out) + "\n"
old = text if text.endswith("\n") else text + "\n"
dest.write_text(new)
print("changed" if new != old else "same")
PY
)"
    if [[ "${changed}" == "changed" ]]; then
        cat "${tmp}" > "${conf}"
        restart_scan_skip_service
    fi
    rm -f "${tmp}"
    trap - EXIT
fi

rk="/etc/rkhunter.conf.local"
if [[ -f "${rk}" && ${#W_SCAN_SKIP_VALID[@]} -gt 0 ]]; then
    for path in "${W_SCAN_SKIP_VALID[@]}"; do
        case "${path}" in
            */.*)
                grep -qxF "ALLOWHIDDENDIR=${path}" "${rk}" \
                    || printf 'ALLOWHIDDENDIR=%s\n' "${path}" >> "${rk}"
                ;;
        esac
    done
fi
exit 0
