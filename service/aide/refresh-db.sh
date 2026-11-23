#!/usr/bin/env bash
# =============================================================================
# File       : service/aide/refresh-db.sh
# Updated at : 2026-11-23
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Rebuild the integrity database under a lock so two refreshes cannot clash.
# -----------------------------------------------------------------------------


run_refresh_db_part_01() {
    set -euo pipefail
    _text_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    _text_hops=0
    while [[ "${_text_hops}" -lt 8 && "${_text_dir}" != "/" ]]; do
        if [[ -f "${_text_dir}/text-load.sh" ]]; then
            # shellcheck disable=SC1090
            source "${_text_dir}/text-load.sh"
            break
        fi
        if [[ -f "${_text_dir}/share/core/text/text-load.sh" ]]; then
            # shellcheck disable=SC1090
            source "${_text_dir}/share/core/text/text-load.sh"
            break
        fi
        if [[ -f "${_text_dir}/core/text/text-load.sh" ]]; then
            # shellcheck disable=SC1090
            source "${_text_dir}/core/text/text-load.sh"
            break
        fi
        _text_dir="$(dirname -- "${_text_dir}")"
        _text_hops=$((_text_hops + 1))
    done
    unset _text_dir _text_hops
    if ! declare -F load_installed_text >/dev/null 2>&1; then
        printf '%s\n' "get_text absent" >&2
        exit 1
    fi
    load_installed_text
}

run_refresh_db_part_02() {
    if [[ "${EUID}" -ne 0 ]]; then
        printf "$(get_text log.run-this-command-with-sudo-n)" >&2
        exit 1
    fi
    if [[ ! -f /etc/aide/aide.conf ]]; then
        printf "$(get_text log.configuration-help-absent-etc-aide-aide-conf-n)" >&2
        exit 1
    fi
    printf '%s\n' "$(get_text log.the-calculation-of-the-fingerprints-can-take-sev)"
    # Two refreshes share this directory. One starts by unlinking database_out
    # while the other aide still has that path open, then the report names a file
    # that is already gone. The lock covers the removal, the init and the install.
    # A waiter keeps the database the holder just installed.
    aide_dir="/var/lib/aide"
    lock_path="${aide_dir}/.refresh.lock"
    stamp_path="${aide_dir}/.refresh.stamp"
    waited=0
    wait_start=0
    if command -v flock >/dev/null 2>&1; then
        mkdir -p -- "${aide_dir}"
        exec 8>>"${lock_path}"
        wait_start="$(date +%s)"
        if ! flock -n 8; then
            waited=1
            flock 8
        fi
    fi
}

run_refresh_db_part_03() {
    if [[ "${waited}" -eq 1 && -f "${stamp_path}" ]]; then
        stamp_value="$(tr -d '[:space:]' <"${stamp_path}")"
        if [[ "${stamp_value}" =~ ^[0-9]+$ && "${stamp_value}" -ge "${wait_start}" ]]; then
            printf '%s\n' "$(get_text log.baseline-help-saved)"
            exit 0
        fi
    fi
    rm -f "${aide_dir}/aide.db.new" "${aide_dir}/aide.db.new.gz"
    set +e
    aide --config=/etc/aide/aide.conf --init
    aide_rc=$?
    set -e
    if [[ -f "${aide_dir}/aide.db.new.gz" ]]; then
        mv -f "${aide_dir}/aide.db.new.gz" "${aide_dir}/aide.db.gz"
        ln -sfn "${aide_dir}/aide.db.gz" "${aide_dir}/aide.db"
    elif [[ -f "${aide_dir}/aide.db.new" ]]; then
        mv -f "${aide_dir}/aide.db.new" "${aide_dir}/aide.db"
    else
        printf '%s\n' "$(get_text log.base-help-not-generated-help-db-new-not-found-de "${aide_rc}")" >&2
        exit 1
    fi
    printf '%s\n' "$(date +%s)" >"${stamp_path}"
}

run_refresh_db_part_04() {
    chmod 600 "${stamp_path}" 2>/dev/null || true
    if [[ "${aide_rc}" -ne 0 ]]; then
        printf '%s\n' "$(get_text log.help-init-a-returned-an-error-detail "${aide_rc}")"
    fi
    printf '%s\n' "$(get_text log.baseline-help-saved)"
}

run_refresh_db_part_05() {
    run_refresh_db_part_01 "$@"
    run_refresh_db_part_02 "$@"
    run_refresh_db_part_03 "$@"
    run_refresh_db_part_04 "$@"
}

run_refresh_db_part_05 "$@"
