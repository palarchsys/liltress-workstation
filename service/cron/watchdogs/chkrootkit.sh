#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/chkrootkit.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================


locate_python_dir() {
    local dir hops=0 candidate
    for candidate in \
        "${CONFIG_BASE_DIRECTORY:-}/python" \
        "${BASE:-}/python" \
        "${INSTALL_DIRECTORY:-}/python" \
        "${INSTALL_DIRECTORY:-}/../share/python"
    do
        if [[ -n "${candidate}" && -d "${candidate}" ]]; then
            (cd -- "${candidate}" && pwd -P)
            return 0
        fi
    done
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        if [[ -d "${dir}/share/python" ]]; then
            printf '%s\n' "${dir}/share/python"
            return 0
        fi
        if [[ -d "${dir}/python" ]]; then
            (cd -- "${dir}/python" && pwd -P)
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

set -euo pipefail
BASE="${BASE:-/opt/liltress-workstation}"
# shellcheck disable=SC1091
source "${BASE}/cron/bin/common.sh"
LOG_FILE="${LOG_DIR}/chkrootkit-${STAMP}.log"
ALERT_FILE="${ALERT_DIR}/chkrootkit-${STAMP}.txt"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${BASE}/src/core/host/fs.sh" ]]; then
    # shellcheck disable=SC1091
    source "${BASE}/src/core/host/fs.sh"
elif [[ -f "${HERE}/../../../core/host/fs.sh" ]]; then
    # shellcheck disable=SC1091
    source "${HERE}/../../../core/host/fs.sh"
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
    IGNORE="${BASE}/src/config/chkrootkit/patterns.ignore"
fi

LOCAL_IGNORE="${BASE}/cron/chkrootkit.local.ignore"
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
    python3 "$(locate_python_dir)/chkrootkit-filter.py" workstation "${LOG_FILE}" "${IGNORE}" "${LOCAL_IGNORE}"
fi
CONFIRMED_COUNT=0
confirmed_tmp="$(mktemp)"
record_quarantine_log chkrootkit "${LOG_FILE}" systemd sshd unbound fail2ban gamescope > "${confirmed_tmp}" || true
if [[ -s "${confirmed_tmp}" ]]; then
    cat "${confirmed_tmp}" >> "${LOG_FILE}"
fi
rm -f "${confirmed_tmp}"
if [[ -s "${LOG_FILE}" ]]; then
    if [[ "${CONFIRMED_COUNT:-0}" -eq 0 ]]; then
        CHKROOTKIT_IGNORE=1 \
            log_alert "$(get_text watchdog.chkrootkit-a-produced-a-output-see "${LOG_FILE}")"
    else
        log_alert "$(get_text watchdog.chkrootkit-a-produced-a-output-see "${LOG_FILE}")"
    fi
elif [[ "${crashed}" -eq 0 ]]; then
    log_pass "$(get_text watchdog.chkrootkit-silencieux-ok)"
fi
exit 0
