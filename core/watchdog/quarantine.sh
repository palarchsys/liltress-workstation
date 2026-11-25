#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/quarantine.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Move a confirmed file aside and remember where it came from.
# -----------------------------------------------------------------------------


# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../boot/python.sh"

# Return 0 when the stored file should be listed in the registry.
check_quarantine_origin() {
    local stored="$1"
    local origin="$2"
    [[ -n "${stored}" && "${stored}" != "absent" && "${stored}" != "inconnue" ]] || return 1
    [[ "${origin}" == /* && "${origin}" != "${stored}" ]] || return 1
    id="$(basename -- "${stored}")"
    [[ "${id}" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+- ]] || return 1
    return 0
}

# The pending file stays beside the registry just written.
write_quarantine_pending() {
    local base="$1"
    local directory="$2"
    local id="$3"
    local quoted=""
    quoted="$(printf '%q' "${id}")"
    printf '%s\n' "sudo bash ${base}/core/quarantine/restore.sh ${quoted}" >>"${directory}/quarantine.pending" || return 0
    chmod 600 "${directory}/quarantine.pending" 2>/dev/null || true
}

# A registry line and a pending restore command are appended.
write_quarantine_origin() {
    local source="$1"
    local origin="$2"
    local stored="$3"
    local signature="$4"
    local id="$5"
    local base="" directory="" registry="" moment=""
    base="$(get_product_base)"
    registry="$(get_watchdog_runtime_file "${base}" quarantine.registry)"
    directory="$(dirname -- "${registry}")"
    if [[ ! -d "${directory}" ]]; then
        mkdir -p "${directory}" 2>/dev/null || return 0
    fi
    [[ -w "${directory}" ]] || return 0
    source="${source//$'\t'/ }"
    origin="${origin//$'\t'/ }"
    stored="${stored//$'\t'/ }"
    signature="${signature//$'\t'/ }"
    signature="${signature//$'\n'/ }"
    moment="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
    printf "$(get_text watchdog.t-t-t-t-t "${id}" "${moment}" "${source}" "${origin}" "${stored}" "${signature}")" \
        >>"${registry}" || return 0
    chmod 600 "${registry}" 2>/dev/null || true
    write_quarantine_pending "${base}" "${directory}" "${id}"
    return 0
}

record_quarantine_origin() {
    local source="$1"
    local origin="$2"
    local stored="$3"
    local signature="${4:-}"
    local id=""
    check_quarantine_origin "${stored}" "${origin}" || return 0
    write_quarantine_origin "${source}" "${origin}" "${stored}" "${signature}" "${id}"
}

# The registry id is printed when the stored path is listed.
read_restore_id() {
    local registry="$1"
    local stored="$2"
    [[ -f "${registry}" && -r "${registry}" ]] || return 0
    awk -F '\t' -v want="${stored}" '$5 == want { print $1; exit }' "${registry}" 2>/dev/null || true
}

# A pending restore command is appended beside the registry.
write_restore_pending() {
    local base="$1"
    local id="$2"
    local quoted="" pending=""
    pending="$(get_watchdog_runtime_file "${base}" quarantine.pending)"
    quoted="$(printf '%q' "${id}")"
    printf '%s\n' "sudo bash ${base}/core/quarantine/restore.sh ${quoted}" >>"${pending}" || return 0
    chmod 600 "${pending}" 2>/dev/null || true
    return 0
}

add_existing_restore() {
    local stored="$1"
    local base="" registry="" id=""
    [[ -n "${stored}" && "${stored}" == /* ]] || return 0
    base="$(get_product_base)"
    registry="$(get_watchdog_runtime_file "${base}" quarantine.registry)"
    id="$(read_restore_id "${registry}" "${stored}")"
    [[ -n "${id}" ]] || return 0
    [[ -w "$(dirname -- "${registry}")" ]] || return 0
    write_restore_pending "${base}" "${id}"
}

take_quarantine_note() {
    local pending body
    pending="$(get_watchdog_runtime_file "$(get_product_base)" quarantine.pending)"
    [[ -s "${pending}" ]] || return 1
    body="$(cat "${pending}" 2>/dev/null || true)"
    [[ -n "${body}" ]] || return 1
    NOTE="$(get_text alert.note.quarantine)"
    NOTE_CMD="${body}"
    rm -f "${pending}" 2>/dev/null || true
    return 0
}

read_quarantine_holder() {
    local target="$1"
    local pid=""
    if command -v lsof >/dev/null 2>&1; then
        pid="$(lsof -t -- "${target}" 2>/dev/null | head -n 1 || true)"
    fi
    if [[ -z "${pid}" ]] && command -v fuser >/dev/null 2>&1; then
        pid="$(fuser -- "${target}" 2>/dev/null | awk '{print $1; exit}' || true)"
    fi
    printf '%s\n' "${pid}"
}

# The caller owns comm. A protected process is described on standard output.
pass_quarantine_holder() {
    local pid="$1"
    local uid=""
    comm=""
    if [[ "${pid}" == "1" ]]; then
        printf '%s\n' "pid 1"
        return 0
    fi
    uid="$(stat -c '%u' "/proc/${pid}" 2>/dev/null || true)"
    if [[ -z "${uid}" || "${uid}" == "0" ]]; then
        printf '%s\n' "uid 0"
        return 0
    fi
    comm="$(cat "/proc/${pid}/comm" 2>/dev/null || true)"
    if [[ -z "${comm}" ]]; then
        printf '%s\n' "$(get_text watchdog.name-absent)"
        return 0
    fi
    return 1
}

write_quarantine_holder() {
    local target="$1"
    shift
    local pid="" comm="" name=""
    QUARANTINE_PID=""
    QUARANTINE_COMM=""
    pid="$(read_quarantine_holder "${target}")"
    [[ -n "${pid}" && "${pid}" =~ ^[0-9]+$ ]] || return 1
    if pass_quarantine_holder "${pid}"; then
        return 0
    fi
    for name in "$@"; do
        if [[ "${comm}" == "${name}" || "${comm}" == "${name}"* ]]; then
            printf '%s\n' "${comm}"
            return 0
        fi
    done
    QUARANTINE_PID="${pid}"
    QUARANTINE_COMM="${comm}"
    return 1
}

# The directory is created with the clamav account when that account exists.
ensure_quarantine_directory() {
    local quarantine="$1"
    if [[ ! -d "${quarantine}" ]]; then
        if id clamav >/dev/null 2>&1; then
            install -d -m 750 -o clamav -g clamav "${quarantine}" 2>/dev/null || true
        else
            install -d -m 750 "${quarantine}" 2>/dev/null || true
        fi
    fi
    [[ -d "${quarantine}" && -w "${quarantine}" ]] || return 1
    return 0
}

# The caller owns MOVE_ACTION and MOVE_STORED.
apply_quarantine_move() {
    local origin="$1"
    local quarantine="$2"
    local base="$3"
    local stamp="" dest=""
    stamp="$(date +%Y%m%d-%H%M%S-%N)"
    dest="${quarantine}/${stamp}-${base}"
    if mv -- "${origin}" "${dest}"; then
        MOVE_ACTION="déplacé en quarantaine"
        MOVE_STORED="${dest}"
        return 0
    fi
    MOVE_STORED="${origin}"
    return 0
}

# An empty or root name is stored as unknown.
read_quarantine_base() {
    local base="$1"
    [[ -n "${base}" && "${base}" != "/" && "${base}" != "." ]] || base="inconnu"
    printf '%s\n' "${base}"
}

take_quarantine_file() {
    local origin="$1"
    local quarantine="" base=""
    quarantine="${CLAMAV_QUARANTINE_DIR:-/var/lib/clamav/quarantine}"
    MOVE_ACTION="déplacement refusé"
    MOVE_STORED="${origin}"
    base="$(basename -- "${origin}")"
    base="$(read_quarantine_base "${base}")"
    ensure_quarantine_directory "${quarantine}" || return 0
    if [[ ! -e "${origin}" ]]; then
        MOVE_ACTION="fichier déjà absent"
        MOVE_STORED="absent"
        return 0
    fi
    if [[ ! -f "${origin}" || -L "${origin}" ]]; then
        return 0
    fi
    apply_quarantine_move "${origin}" "${quarantine}" "${base}"
    return 0
}

# TERM is reported as accepted or rejected.
signal_quarantine_pid() {
    local pid="$1"
    local comm="$2"
    if kill -TERM "${pid}" 2>/dev/null; then
        printf '%s\n' "$(get_text watchdog.process-stopped "${pid}" "${comm}")"
    else
        printf '%s\n' "$(get_text watchdog.process-not-stopped-signal-rejected "${pid}")"
    fi
}

signal_quarantine_holder() {
    local origin="$1"
    local stored="$2"
    shift 2
    local target pid comm reason
    for target in "${origin}" "${stored}"; do
        [[ -n "${target}" && "${target}" != "absent" && -e "${target}" ]] || continue
        if reason="$(write_quarantine_holder "${target}" "$@")"; then
            printf '%s\n' "$(get_text watchdog.process-not-stopped "${reason}")"
            return 0
        fi
        pid="${QUARANTINE_PID:-}"
        comm="${QUARANTINE_COMM:-}"
        [[ -n "${pid}" ]] || continue
        signal_quarantine_pid "${pid}" "${comm}"
        return 0
    done
    printf '%s\n' "$(get_text watchdog.process-not-stopped-no-d-tenteur)"
}

# The caller owns quarantine_kept. A protected path stays in place.
skip_quarantine_path() {
    local path="$1"
    shift
    local reason=""
    quarantine_kept=0
    case "${path}" in
        /etc/passwd | /etc/shadow | /etc/sudoers | /etc/ssh/sshd_config | /etc/ufw/ufw.conf | /usr/bin/sudo | /usr/bin/passwd | /usr/sbin/sshd)
            printf '%s\n' "$(get_text watchdog.not-updated-in-quarantine "${path}")"
            quarantine_kept=1
            return 0
            ;;
    esac
    if reason="$(write_quarantine_holder "${path}" "$@")"; then
        printf '%s\n' "$(get_text watchdog.not-updated-in-quarantine "${reason}")"
        quarantine_kept=1
        return 0
    fi
    return 0
}

# Return 0 when this path can be moved aside.
pass_quarantine_hit() {
    local path="$1"
    local quarantine="$2"
    [[ -n "${path}" ]] || return 1
    case "${path}" in
        "${quarantine}" | "${quarantine}"/*) return 1 ;;
    esac
    [[ -f "${path}" && ! -L "${path}" ]] || return 1
    return 0
}

# One infected path is moved or described. Protected paths stay in place.
record_quarantine_hit() {
    local source="$1"
    local path="$2"
    shift 2
    local phrase="" quarantine="" quarantine_kept=0
    quarantine="${CLAMAV_QUARANTINE_DIR:-/var/lib/clamav/quarantine}"
    pass_quarantine_hit "${path}" "${quarantine}" || return 0
    CONFIRMED_COUNT=$((CONFIRMED_COUNT + 1))
    skip_quarantine_path "${path}" "$@"
    if [[ "${quarantine_kept}" -eq 1 ]]; then
        return 0
    fi
    take_quarantine_file "${path}"
    if [[ "${MOVE_ACTION}" != "déplacé en quarantaine" ]]; then
        printf '%s\n' "${MOVE_ACTION} : ${path}"
        return 0
    fi
    record_quarantine_origin "${source}" "${path}" "${MOVE_STORED}" "${source}" || true
    phrase="$(signal_quarantine_holder "${path}" "${MOVE_STORED}" "$@")"
    printf '%s\n' "$(get_text watchdog.moved-in-quarantine-quarantine "${path}" "${phrase}" "${MOVE_STORED}")"
    MOVED_COUNT=$((MOVED_COUNT + 1))
    return 0
}

record_quarantine_log() {
    local source="$1"
    local log="$2"
    shift 2
    local path=""
    CONFIRMED_COUNT=0
    MOVED_COUNT=0
    [[ -n "${log}" && -f "${log}" ]] || return 0
    while IFS= read -r path; do
        record_quarantine_hit "${source}" "${path}" "$@"
    done < <(
        python3 "$(locate_python_directory)/alert-quarantine.py" "${source}" "${log}"
    )
    return 0
}
