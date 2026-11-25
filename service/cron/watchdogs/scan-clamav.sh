#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/scan-clamav.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Walk the configured roots and report infections.
# Note       : The on-access skip list stays inside the walk.
# Note       : An empty size cap keeps every regular file.
# -----------------------------------------------------------------------------


read_scan_run_directory() {
    local candidate="" line=""
    for candidate in \
        "${BASE:-}/config/service/clamav/scan.conf" \
        "${CONFIG_BASE_DIRECTORY:-}/config/service/clamav/scan.conf" \
        "${INSTALL_DIRECTORY:-}/config/service/clamav/scan.conf"; do
        [[ -n "${candidate}" && -f "${candidate}" ]] || continue
        while IFS= read -r line || [[ -n "${line}" ]]; do
            case "${line}" in
                run-directory=*)
                    printf '%s\n' "${line#run-directory=}"
                    return 0
                    ;;
            esac
        done <"${candidate}"
    done
    printf '%s\n' "/run/liltress-workstation"
}

read_scan_value() {
    local key="$1"
    local candidate="" line=""
    for candidate in \
        "${BASE:-}/config/service/clamav/scan.conf" \
        "${CONFIG_BASE_DIRECTORY:-}/config/service/clamav/scan.conf" \
        "${INSTALL_DIRECTORY:-}/config/service/clamav/scan.conf"; do
        [[ -n "${candidate}" && -f "${candidate}" ]] || continue
        while IFS= read -r line || [[ -n "${line}" ]]; do
            case "${line}" in
                ${key}=*)
                    printf '%s\n' "${line#*=}"
                    return 0
                    ;;
            esac
        done <"${candidate}"
    done
    return 1
}

locate_scan_file() {
    local name="$1"
    local candidate=""
    for candidate in \
        "${BASE:-}/config/service/clamav/${name}" \
        "${CONFIG_BASE_DIRECTORY:-}/config/service/clamav/${name}" \
        "${INSTALL_DIRECTORY:-}/config/service/clamav/${name}"; do
        [[ -n "${candidate}" && -f "${candidate}" ]] || continue
        printf '%s\n' "${candidate}"
        return 0
    done
    return 1
}

read_listed_paths() {
    local file="$1"
    local line="" rendered=""
    [[ -f "${file}" ]] || return 0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" || "${line}" == \#* ]] && continue
        rendered="${line//__HF_BASE__/${BASE}}"
        rendered="${rendered//__BASE__/${BASE}}"
        printf '%s\n' "${rendered}"
    done <"${file}"
}

add_prune_term() {
    local path="$1"
    if [[ "${path}" == /* ]]; then
        PRUNE_TERMS+=(-path "${path}" -o -path "${path}/*" -o)
        return 0
    fi
    PRUNE_TERMS+=(-path "*/${path}" -o -path "*/${path}/*" -o)
}

load_scan_roots() {
    local file="" line=""
    SCAN_ROOTS=()
    file="$(locate_scan_file scan-roots.paths || true)"
    [[ -n "${file}" ]] || return 0
    while IFS= read -r line; do
        [[ -d "${line}" ]] || continue
        SCAN_ROOTS+=("${line}")
    done < <(read_listed_paths "${file}")
}

load_scan_prunes() {
    local file="" line=""
    PRUNE_TERMS=()
    file="$(locate_scan_file scan-prune.paths || true)"
    [[ -n "${file}" ]] || return 0
    while IFS= read -r line; do
        [[ -n "${line}" ]] || continue
        add_prune_term "${line}"
    done < <(read_listed_paths "${file}")
}

init_run_file() {
    local run_directory=""
    run_directory="$(read_scan_run_directory)"
    if ! install -d -m 755 "${run_directory}" 2>/dev/null; then
        run_directory="${BASE}/cron"
        mkdir -p -- "${run_directory}"
    fi
    mktemp -p "${run_directory}"
}

log_scan_pass() {
    printf '%s\n' "$*"
}

take_clamav_lock() {
    local run_directory=""
    run_directory="$(read_scan_run_directory)"
    install -d -m 755 "${run_directory}" 2>/dev/null || mkdir -p -- "${run_directory}"
    if [[ ! -d "${run_directory}" ]]; then
        run_directory="${BASE}/cron"
        mkdir -p -- "${run_directory}"
    fi
    exec 9>"${run_directory}/clamav.lock"
    if ! flock -n 9; then
        log_scan_pass "$(get_text watchdog.scan-clamav-already-in-progress)"
        exit 0
    fi
}

write_quarantine_note() {
    local count="$1"
    printf '%s\n' "$(get_text watchdog.quarantine)" >>"${LOG_FILE}"
    printf '%s\n' "$(get_text watchdog.count-of-files-in-quarantine "${count}")" >>"${LOG_FILE}"
    if [[ "${count}" -eq 0 ]]; then
        return 0
    fi
    find "${QUARANTINE_DIR}" -type f ! -name '.clamav-quarantine-lock.*' -printf '%p\n' 2>/dev/null | sort >>"${LOG_FILE}" || true
}

get_clam_mode() {
    CLAM_MODE=scan
    if [[ -S /run/clamav/clamd.ctl || -S /var/run/clamav/clamd.ctl ]]; then
        CLAM_MODE=daemon
        export CLAM_MODE
        return 0
    fi
    if command -v clamdscan >/dev/null 2>&1 && clamdscan --ping 3 >/dev/null 2>&1; then
        CLAM_MODE=daemon
    fi
    export CLAM_MODE
}

write_walk_list() {
    local list="$1"
    local max_size="$2"
    local -a size_terms=()
    if [[ "${#PRUNE_TERMS[@]}" -gt 0 ]]; then
        unset 'PRUNE_TERMS[-1]'
    fi
    if [[ -n "${max_size}" ]]; then
        size_terms+=(! -size "+${max_size}")
    fi
    if [[ "${#PRUNE_TERMS[@]}" -gt 0 ]]; then
        find "${SCAN_ROOTS[@]}" \( "${PRUNE_TERMS[@]}" \) -prune -o -type f "${size_terms[@]}" -print0 >"${list}" 2>>"${LOG_FILE}" || true
        return 0
    fi
    find "${SCAN_ROOTS[@]}" -type f "${size_terms[@]}" -print0 >"${list}" 2>>"${LOG_FILE}" || true
}

set_clamav_hits() {
    local line="" body="" virus="" origin="" response=""
    local -a found_lines=()
    mapfile -t found_lines < <(grep ' FOUND$' "${LOG_FILE}" || true)
    response="${HERE}/clamav-response.sh"
    if [[ -x "${BASE}/service/cron/watchdogs/clamav-response.sh" ]]; then
        response="${BASE}/service/cron/watchdogs/clamav-response.sh"
    fi
    for line in "${found_lines[@]+"${found_lines[@]}"}"; do
        body="${line% FOUND}"
        virus="${body##*: }"
        origin="${body%:*}"
        [[ -n "${origin}" && -n "${virus}" ]] || continue
        CLAMAV_EVENT_FILE="${origin}" \
            CLAMAV_EVENT_VIRUS="${virus}" \
            CLAMAV_EVENT_KIND=periodic \
            CLAMAV_EVENT_MAIL=0 \
            CLAMAV_RESPONSE_STAMP="${STAMP}-$$" \
            bash "${response}" || true
    done
    log_alert "$(get_text watchdog.clamscan-infection-s-see "${LOG_FILE}")"
}

report_walk_hits() {
    local rc="$1"
    local kind=""
    kind="$(get_clamav_kind "${LOG_FILE}")"
    if [[ "${kind}" == "ok" && "${rc}" -ne 0 ]]; then
        kind="error"
    fi
    report_clamav || true
    if [[ "${kind}" == "infected" ]]; then
        set_clamav_hits
        return 0
    fi
    if [[ "${kind}" == "error" ]]; then
        log_alert "$(get_text watchdog.clamscan-error-rc "${rc}")"
        return 0
    fi
    if ! grep -q 'clamscan planté signal' "${LOG_FILE}"; then
        log_scan_pass "clamscan OK"
    fi
}

run_clamav_walk() {
    local list="" rc=0 max_size=""
    max_size="$(read_scan_value max-size || true)"
    list="$(init_run_file)"
    trap 'rm -f "${list}"' EXIT
    write_walk_list "${list}" "${max_size}"
    set +e
    trap '' PIPE
    list_clamav_scan "${list}" >>"${LOG_FILE}" 2>&1
    rc=$?
    trap - PIPE
    set -e
    report_walk_hits "${rc}"
}

clamav_scan_01_run_01_take() {
    set -euo pipefail
    HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -r "${HERE}/watchdog.conf" ]]; then
        # shellcheck disable=SC1091
        source "${HERE}/watchdog.conf"
    fi
    if [[ -z "${BASE:-}" && -z "${CONFIG_BASE_DIRECTORY:-}" && -n "${CONFIG_BASE_DIRECTORY+x}" ]]; then
        exit 0
    fi
    # shellcheck disable=SC1091
    source "${HERE}/common.sh"
    if [[ -z "${BASE:-}" ]]; then
        BASE="${CONFIG_BASE_DIRECTORY:-/opt/liltress-workstation}"
    fi
    STAMP="${STAMP:-$(date +%Y%m%d-%H%M%S)}"
    LOG_DIR="${LOG_DIR:-${BASE}/cron/security_logs}"
    ALERT_DIR="${ALERT_DIR:-${BASE}/cron/alerts}"
    mkdir -p -- "${LOG_DIR}" "${ALERT_DIR}"
    LOG_FILE="${LOG_DIR}/clamav-${STAMP}.log"
    ALERT_FILE="${ALERT_DIR}/clamav-${STAMP}.txt"
    MODULE_NAME="Clamav"
    QUARANTINE_DIR="/var/lib/clamav/quarantine"
    : >"${LOG_FILE}"
    take_clamav_lock
    get_clam_mode
}

clamav_scan_01_run_02_get() {
    if [[ "${CLAM_MODE}" != "daemon" ]] && ! command -v clamscan >/dev/null 2>&1; then
        log_scan_pass "$(get_text watchdog.clamscan-absent-skip)"
        exit 0
    fi
    count="$(find "${QUARANTINE_DIR}" -type f ! -name '.clamav-quarantine-lock.*' -printf '%p\n' 2>/dev/null | wc -l)"
    count="$(printf '%s\n' "${count}" | tr -d '[:space:]')"
    write_quarantine_note "${count}"
    load_scan_roots
    load_scan_prunes
    if [[ "${#SCAN_ROOTS[@]}" -eq 0 ]]; then
        if [[ "${count}" -gt 0 ]]; then
            log_alert "$(get_text watchdog.clamscan-infection-s-see "${LOG_FILE}")"
        fi
        exit 0
    fi
    run_clamav_walk
    if [[ "${count}" -gt 0 ]] && ! grep -q ' FOUND$' "${LOG_FILE}"; then
        log_alert "$(get_text watchdog.clamscan-infection-s-see "${LOG_FILE}")"
    fi
    exit 0
}

clamav_scan_01_run_03_run() {
    clamav_scan_01_run_01_take "$@"
    clamav_scan_01_run_02_get "$@"
}

clamav_scan_01_run_03_run "$@"
