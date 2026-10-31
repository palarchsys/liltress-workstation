#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/clamav.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================
# -----------------------------------------------------------------------------
# Purpose    : Boot and periodic ClamAV walk of /home, /opt and /tmp.
# Note       : G_CLAM_MODE=daemon selects the running daemon in the shared scanner.
# Note       : The file list is created under /run/liltress-workstation.
# Note       : An anchored OnAccessExcludePath is pruned as its path.
# Note       : W_CLAMAV_DEFER=1 skips the pass while a game is running.
# -----------------------------------------------------------------------------

set -euo pipefail
W_BASE="${W_BASE:-/opt/liltress-workstation}"
# shellcheck disable=SC1091
source "${W_BASE}/cron/bin/common.sh"
LOG_FILE="${LOG_DIR}/clamav-${STAMP}.log"
ALERT_FILE="${ALERT_DIR}/clamav-${STAMP}.txt"
if ! command -v clamscan >/dev/null; then
    log_pass "$(get_text watchdog.clamscan-absent-skip)"
    exit 0
fi

install -d -m 755 /run/liltress-workstation
exec 9>/run/liltress-workstation/clamav.lock
if ! flock -n 9; then
    log_pass "$(get_text watchdog.scan-clamav-already-in-progress)"
    exit 0
fi

if [[ "${W_CLAMAV_DEFER:-0}" == "1" ]]; then
    busy=""
    for name in lutris heroic gamescope; do
        if pgrep -x "${name}" >/dev/null 2>&1; then
            busy="${name}"
            break
        fi
    done
    if [[ -n "${busy}" ]]; then
        log_pass "$(get_text watchdog.scan-clamav-report-e-runs "${busy}")"
        exit 0
    fi
fi

if [[ -S /run/clamav/clamd.ctl || -S /var/run/clamav/clamd.ctl ]]; then
    G_CLAM_MODE=daemon
    export G_CLAM_MODE
fi

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/scan-skip-lib.sh"
collect_scan_skip_path

excludes=()
if [[ -f /etc/clamav/clamd.conf ]]; then
    while read -r path; do
        [[ -n "${path}" ]] && excludes+=("${path}")
    done < <(awk '/^OnAccessExcludePath[[:space:]]/{
        p = $2
        sub(/^\^/, "", p)
        sub(/\$$/, "", p)
        gsub(/\\/, "", p)
        print p
    }' /etc/clamav/clamd.conf)
fi

prune_names=(
    proc sys dev
    var/lib/libvirt var/lib/docker
    libvirt
    snap-private-tmp
)

find_args=()
for path in "${excludes[@]}"; do
    find_args+=( -path "${path}" -o -path "${path}/*" -o )
done
if [[ ${#W_SCAN_SKIP_VALID[@]} -gt 0 ]]; then
    for path in "${W_SCAN_SKIP_VALID[@]}"; do
        find_args+=( -path "${path}" -o -path "${path}/*" -o )
    done
fi
for name in "${prune_names[@]}"; do
    find_args+=( -path "*/${name}" -o -path "*/${name}/*" -o )
done
unset 'find_args[-1]'

file_list="$(mktemp -p /run/liltress-workstation)"
trap 'rm -f "${file_list}"' EXIT
find /home /opt /tmp \
    \( "${find_args[@]}" \) -prune -o -type f ! -size +25M -print0 \
    > "${file_list}" 2>>"${LOG_FILE}" || true

set +e
trap '' PIPE
list_clamav_scan "${file_list}" >> "${LOG_FILE}" 2>&1
rc=$?
trap - PIPE
set -e
kind="$(get_clamav_kind "${LOG_FILE}")"
if [[ "${kind}" == "ok" && "${rc}" -ne 0 ]]; then
    kind="error"
fi

report_clamav || true
if [[ "${kind}" == "infected" ]]; then
    mapfile -t found_lines < <(grep ' FOUND$' "${LOG_FILE}" || true)
    response="${HERE}/clamav-response.sh"
    [[ -x "${W_BASE}/cron/bin/clamav-response.sh" ]] && response="${W_BASE}/cron/bin/clamav-response.sh"
    for line in "${found_lines[@]+"${found_lines[@]}"}"; do
        body="${line% FOUND}"
        virus="${body##*: }"
        origin="${body%:*}"
        [[ -n "${origin}" && -n "${virus}" ]] || continue
        W_CLAMAV_EVENT_FILE="${origin}" \
        W_CLAMAV_EVENT_VIRUS="${virus}" \
        W_CLAMAV_EVENT_KIND=periodic \
        W_CLAMAV_EVENT_MAIL=0 \
        W_CLAMAV_RESPONSE_STAMP="${STAMP}-$$" \
            bash "${response}" || true
    done
    log_alert "$(get_text watchdog.clamscan-infection-s-see "${LOG_FILE}")"
elif [[ "${kind}" == "error" ]]; then
    log_alert "$(get_text watchdog.clamscan-error-rc "${rc}")"
elif ! grep -q 'clamscan planté signal' "${LOG_FILE}"; then
    log_pass "clamscan OK"
fi
exit 0
