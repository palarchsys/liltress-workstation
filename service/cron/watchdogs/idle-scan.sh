#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/idle-scan.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

set -euo pipefail
W_BASE="${W_BASE:-/opt/liltress-workstation}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${W_BASE}/cron/bin/common.sh"
# shellcheck disable=SC1091
source "${HERE}/scan-skip-lib.sh"
LOG_FILE="${LOG_DIR}/idle-scan-${STAMP}.log"
ALERT_FILE="${ALERT_DIR}/idle-scan-${STAMP}.txt"
: > "${LOG_FILE}"
arm_crash_mail "analyse différée"

busy=""
for name in lutris heroic gamescope; do
    if pgrep -x "${name}" >/dev/null 2>&1; then
        busy="${name}"
        break
    fi
done
if [[ -n "${busy}" ]]; then
    log_pass "$(get_text watchdog.password-deferred-report-e-runs "${busy}")"
    exit 0
fi

if ! command -v clamscan >/dev/null; then
    log_pass "$(get_text watchdog.clamscan-absent-skip)"
    exit 0
fi

collect_scan_skip_path
install -d -m 755 /run/liltress-workstation
file_list="$(mktemp -p /run/liltress-workstation)"
fresh_list=""
trap 'st=$?; rm -f "${file_list}"; if [[ -n "${fresh_list}" ]]; then rm -f "${fresh_list}"; fi; send_crash_mail "${st}"' EXIT
stamp="${W_BASE}/cron/scan-skip.stamp"
if [[ ${#W_SCAN_SKIP_VALID[@]} -gt 0 ]]; then
    for path in "${W_SCAN_SKIP_VALID[@]}"; do
        base="$(basename "${path}")"
        [[ "${base}" == ".cache" || "${base}" == "snap" ]] && continue
        [[ -e "${path}" ]] || continue
        if [[ -f "${path}" ]]; then
            printf '%s\0' "${path}" >> "${file_list}"
            continue
        fi
        [[ -d "${path}" ]] || continue
        if [[ -f "${stamp}" ]]; then
            find "${path}" \
                \( -path '*/shadercache' -o -path '*/shadercache/*' \
                    -o -path '*/downloading' -o -path '*/downloading/*' \) -prune -o \
                -type f \( -perm /111 -o \( ! -size +25M -newer "${stamp}" \) \) -print0 \
                >> "${file_list}" 2>>"${LOG_FILE}" || true
        else
            find "${path}" \
                \( -path '*/shadercache' -o -path '*/shadercache/*' \
                    -o -path '*/downloading' -o -path '*/downloading/*' \) -prune -o \
                -type f \( -perm /111 -o ! -size +25M \) -print0 \
                >> "${file_list}" 2>>"${LOG_FILE}" || true
        fi
    done
fi

set +e
trap '' PIPE
if [[ -s "${file_list}" ]]; then
    list_clamav_scan "${file_list}" >> "${LOG_FILE}" 2>&1
    rc=$?
else
    rc=0
fi
trap - PIPE
set -e
kind="ok"
crashed=0
if [[ -s "${file_list}" ]]; then
    kind="$(get_clamav_kind "${LOG_FILE}")"
    if [[ "${kind}" == "ok" && "${rc}" -ne 0 ]]; then
        kind="error"
    fi
    if report_clamav; then
        crashed=1
    fi
fi

seen="${W_BASE}/cron/scan-skip.seen"
if [[ "${kind}" == "error" ]]; then
    log_alert "$(get_text watchdog.clamscan-error-rc "${rc}")"
    exit 0
fi
if [[ "${kind}" == "infected" ]]; then
    fresh_list="$(mktemp -p /run/liltress-workstation)"
    python3 - "${LOG_FILE}" "${seen}" > "${fresh_list}" << 'PY'
import sys
from pathlib import Path

log = Path(sys.argv[1]).read_text(errors="replace").splitlines()
seen_path = Path(sys.argv[2])
known = set()
if seen_path.is_file():
    known = {line for line in seen_path.read_text(errors="replace").splitlines() if line}
fresh = []
for line in log:
    if not line.endswith(" FOUND"):
        continue
    body = line[:-6]
    if ": " not in body:
        continue
    path, sig = body.rsplit(": ", 1)
    key = sig + "\t" + path
    if key in known or key in fresh:
        continue
    fresh.append(key)
if fresh:
    with seen_path.open("a", encoding="utf-8") as handle:
        for key in fresh:
            handle.write(key + "\n")
    for key in fresh:
        print(key)
PY
    chmod 600 "${seen}" 2>/dev/null || true
    new_count=0
    if [[ -s "${fresh_list}" ]]; then
        response="${HERE}/clamav-response.sh"
        [[ -x "${W_BASE}/cron/bin/clamav-response.sh" ]] && response="${W_BASE}/cron/bin/clamav-response.sh"
        while IFS=$'\t' read -r sig origin; do
            [[ -n "${sig}" && -n "${origin}" ]] || continue
            new_count=$((new_count + 1))
            W_CLAMAV_EVENT_FILE="${origin}" \
            W_CLAMAV_EVENT_VIRUS="${sig}" \
            W_CLAMAV_EVENT_KIND=idle \
            W_CLAMAV_EVENT_MAIL=0 \
            W_CLAMAV_RESPONSE_STAMP="${STAMP}-$$-${new_count}" \
                bash "${response}" || true
        done < "${fresh_list}"
    fi
    if [[ "${new_count}" -gt 0 ]]; then
        log_alert "$(get_text watchdog.clamscan-infection-s-see "${LOG_FILE}")"
    else
        log_pass "$(get_text watchdog.infections-already-signal-es)"
    fi
    exit 0
fi
if [[ "${crashed}" -eq 1 ]]; then
    exit 0
fi

touch "${stamp}"
chmod 644 "${stamp}"
log_pass "clamscan OK"
exit 0
