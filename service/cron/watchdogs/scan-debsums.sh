#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/scan-debsums.sh
# Updated at : 2026-11-21
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Record package checksum changes on this host.
# Note       : A crashed tool still keeps the partial log.
# -----------------------------------------------------------------------------


# The caller owns shown_python and reads it after this call.
show_python_directory() {
    local candidate="$1"
    shown_python=0
    [[ -n "${candidate}" && -d "${candidate}" ]] || return 0
    (cd -- "${candidate}" && pwd -P)
    shown_python=1
    return 0
}

# The shared directory is printed as given, without resolving links.
show_share_python() {
    local dir="$1"
    shown_python=0
    if [[ ! -d "${dir}/share/python" ]]; then
        return 0
    fi
    printf '%s\n' "${dir}/share/python"
    shown_python=1
    return 0
}

locate_python_dir() {
    local dir="" hops=0 candidate="" shown_python=0
    for candidate in \
        "${CONFIG_BASE_DIRECTORY:-}/python" \
        "${BASE:-}/python" \
        "${INSTALL_DIRECTORY:-}/python" \
        "${INSTALL_DIRECTORY:-}/../share/python"; do
        show_python_directory "${candidate}"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
    done
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        show_share_python "${dir}"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
        show_python_directory "${dir}/python"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

read_host_mode() {
    local candidate="" line=""
    HOST_MODE="workstation"
    for candidate in \
        "${BASE:-}/config/service/watchdog/host.list" \
        "${CONFIG_BASE_DIRECTORY:-}/config/service/watchdog/host.list" \
        "${INSTALL_DIRECTORY:-}/config/service/watchdog/host.list"; do
        [[ -n "${candidate}" && -f "${candidate}" ]] || continue
        line="$(grep -v '^#' "${candidate}" | head -n 1 || true)"
        [[ -n "${line}" ]] && HOST_MODE="${line}"
        return 0
    done
}

set -euo pipefail
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"
LOG_FILE="${LOG_DIR}/debsums-${STAMP}.log"
ALERT_FILE="${ALERT_DIR}/debsums-${STAMP}.txt"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
IGNORE="${HERE}/debsums.ignore"
LOCAL_IGNORE="${BASE}/cron/debsums.local.ignore"
if ! command -v debsums >/dev/null; then
    log_pass "$(get_text watchdog.debsums-absent-skip)"
    exit 0
fi
read_host_mode
set +e
debsums -s >"${LOG_FILE}" 2>&1
rc=$?
set -e
crashed=0
if [[ "${rc}" -ge 128 ]]; then
    log_alert "$(get_crash_sentence "debsums" "${rc}")"
    crashed=1
fi
if [[ "${HOST_MODE}" == "server" ]]; then
    python3 "$(locate_python_dir)/debsums-filter.py" server "${LOG_FILE}" "${BASE}"
else
    python3 "$(locate_python_dir)/debsums-filter.py" workstation "${LOG_FILE}" "${IGNORE}" "${LOCAL_IGNORE}" "${BASE}"
fi
if [[ "${crashed}" -eq 0 && -s "${LOG_FILE}" ]]; then
    summary="$(reset_debsums_log "${LOG_FILE}")"
    if [[ -n "${summary}" ]]; then
        log_alert "${summary}"
    fi
elif [[ "${crashed}" -eq 0 ]]; then
    log_pass "debsums OK"
fi
exit 0
