#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/quarantine.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================


locate_python_dir() {
    local dir hops=0
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        if [[ -d "${dir}/share/python" ]]; then
            printf '%s\n' "${dir}/share/python"
            return 0
        fi
        if [[ -d "${dir}/python" ]]; then
            printf '%s\n' "${dir}/python"
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}


record_quarantine_origin() {
    local source="$1"
    local origin="$2"
    local stored="$3"
    local signature="${4:-}"
    local base dir registry id moment quoted
    [[ -n "${stored}" && "${stored}" != "absent" && "${stored}" != "inconnue" ]] || return 0
    [[ "${origin}" == /* && "${origin}" != "${stored}" ]] || return 0
    id="$(basename -- "${stored}")"
    [[ "${id}" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+- ]] || return 0
    base="$(get_product_base)"
    registry="$(watchdog_runtime_file "${base}" quarantine.registry)"
    dir="$(dirname -- "${registry}")"
    if [[ ! -d "${dir}" ]]; then
        mkdir -p "${dir}" 2>/dev/null || return 0
    fi
    [[ -w "${dir}" ]] || return 0
    source="${source//$'\t'/ }"
    origin="${origin//$'\t'/ }"
    stored="${stored//$'\t'/ }"
    signature="${signature//$'\t'/ }"
    signature="${signature//$'\n'/ }"
    moment="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
    printf "$(get_text watchdog.t-t-t-t-t "${id}" "${moment}" "${source}" "${origin}" "${stored}" "${signature}")" \
        >> "${registry}" || return 0
    chmod 600 "${registry}" 2>/dev/null || true
    quoted="$(printf '%q' "${id}")"
    printf '%s\n' "sudo bash ${base}/bin/quarantine-restore.sh ${quoted}" >> "${dir}/quarantine.pending" || return 0
    chmod 600 "${dir}/quarantine.pending" 2>/dev/null || true
    return 0
}

add_existing_restore() {
    local stored="$1"
    local base registry id quoted
    [[ -n "${stored}" && "${stored}" == /* ]] || return 0
    base="$(get_product_base)"
    registry="$(watchdog_runtime_file "${base}" quarantine.registry)"
    [[ -f "${registry}" && -r "${registry}" ]] || return 0
    id="$(awk -F '\t' -v want="${stored}" '$5 == want { print $1; exit }' "${registry}" 2>/dev/null || true)"
    [[ -n "${id}" ]] || return 0
    [[ -w "$(dirname -- "${registry}")" ]] || return 0
    quoted="$(printf '%q' "${id}")"
    printf '%s\n' "sudo bash ${base}/bin/quarantine-restore.sh ${quoted}" >> "$(watchdog_runtime_file "${base}" quarantine.pending)" || return 0
    chmod 600 "$(watchdog_runtime_file "${base}" quarantine.pending)" 2>/dev/null || true
    return 0
}

take_quarantine_note() {
    local pending body
    pending="$(watchdog_runtime_file "$(get_product_base)" quarantine.pending)"
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

write_quarantine_holder() {
    local target="$1"
    shift
    local pid="" comm="" uid="" name=""
    QUARANTINE_PID=""
    QUARANTINE_COMM=""
    pid="$(read_quarantine_holder "${target}")"
    [[ -n "${pid}" && "${pid}" =~ ^[0-9]+$ ]] || return 1
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

take_quarantine_file() {
    local origin="$1"
    local quarantine base stamp dest
    quarantine="${CLAMAV_QUARANTINE_DIR:-/var/lib/clamav/quarantine}"
    MOVE_ACTION="déplacement refusé"
    MOVE_STORED="${origin}"
    base="$(basename -- "${origin}")"
    [[ -n "${base}" && "${base}" != "/" && "${base}" != "." ]] || base="inconnu"
    if [[ ! -d "${quarantine}" ]]; then
        if id clamav >/dev/null 2>&1; then
            install -d -m 750 -o clamav -g clamav "${quarantine}" 2>/dev/null || true
        else
            install -d -m 750 "${quarantine}" 2>/dev/null || true
        fi
    fi
    if [[ ! -d "${quarantine}" || ! -w "${quarantine}" ]]; then
        return 0
    fi
    if [[ ! -e "${origin}" ]]; then
        MOVE_ACTION="fichier déjà absent"
        MOVE_STORED="absent"
        return 0
    fi
    if [[ ! -f "${origin}" || -L "${origin}" ]]; then
        return 0
    fi
    stamp="$(date +%Y%m%d-%H%M%S-%N)"
    dest="${quarantine}/${stamp}-${base}"
    if mv -- "${origin}" "${dest}"; then
        MOVE_ACTION="déplacé en quarantaine"
        MOVE_STORED="${dest}"
    else
        MOVE_STORED="${origin}"
    fi
    return 0
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
        if kill -TERM "${pid}" 2>/dev/null; then
            printf '%s\n' "$(get_text watchdog.process-stopped "${pid}" "${comm}")"
        else
            printf '%s\n' "$(get_text watchdog.process-not-stopped-signal-rejected "${pid}")"
        fi
        return 0
    done
    printf '%s\n' "$(get_text watchdog.process-not-stopped-no-d-tenteur)"
}

record_quarantine_log() {
    local source="$1"
    local log="$2"
    shift 2
    local path reason phrase quarantine
    CONFIRMED_COUNT=0
    MOVED_COUNT=0
    [[ -n "${log}" && -f "${log}" ]] || return 0
    quarantine="${CLAMAV_QUARANTINE_DIR:-/var/lib/clamav/quarantine}"
    while IFS= read -r path; do
        [[ -n "${path}" ]] || continue
        case "${path}" in
            "${quarantine}"|"${quarantine}"/*) continue ;;
        esac
        [[ -f "${path}" && ! -L "${path}" ]] || continue
        CONFIRMED_COUNT=$((CONFIRMED_COUNT + 1))
        case "${path}" in
            /etc/passwd|/etc/shadow|/etc/sudoers|/etc/ssh/sshd_config|/etc/ufw/ufw.conf|/usr/bin/sudo|/usr/bin/passwd|/usr/sbin/sshd)
                printf '%s\n' "$(get_text watchdog.not-updated-in-quarantine "${path}")"
                continue
                ;;
        esac
        if reason="$(write_quarantine_holder "${path}" "$@")"; then
            printf '%s\n' "$(get_text watchdog.not-updated-in-quarantine "${reason}")"
            continue
        fi
        take_quarantine_file "${path}"
        if [[ "${MOVE_ACTION}" != "déplacé en quarantaine" ]]; then
            printf '%s\n' "${MOVE_ACTION} : ${path}"
            continue
        fi
        record_quarantine_origin "${source}" "${path}" "${MOVE_STORED}" "${source}" || true
        phrase="$(signal_quarantine_holder "${path}" "${MOVE_STORED}" "$@")"
        printf '%s\n' "$(get_text watchdog.moved-in-quarantine-quarantine "${path}" "${phrase}" "${MOVE_STORED}")"
        MOVED_COUNT=$((MOVED_COUNT + 1))
    done < <(python3 "$(locate_python_dir)/alert-quarantine.py" "${source}" "${log}"
    )
    return 0
}
