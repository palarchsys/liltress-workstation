#!/usr/bin/env bash
# =============================================================================
# File       : core/mail/mail-test.sh
# Updated at : 2026-11-13
# Creator    : palarchsys
# =============================================================================
# -----------------------------------------------------------------------------
# Purpose    : Send one sample alert so the width and the height can be seen.
# Note       : The recipient stays in the installed configuration.
# -----------------------------------------------------------------------------

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
for candidate in \
    "${script_dir}/log.sh" \
    "${script_dir}/../core/log/log.sh" \
    "${script_dir}/../log/log.sh" \
    "${script_dir}/../core/log/log.sh" \
    "${CONFIG_BASE_DIRECTORY:-}/core/log/log.sh" \
    "${INSTALL_DIRECTORY:-}/core/log/log.sh" \
    "${INSTALL_DIRECTORY:-}/core/log/log.sh"
do
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
        # shellcheck disable=SC1090
        source "${candidate}"
        break
    fi
done

send_mail_test() {
    local script_dir base send_sh wide err_file
    if ! declare -F get_text >/dev/null 2>&1; then
        printf '%s\n' "get_text absent" >&2
        exit 1
    fi
    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    if [[ "$(basename -- "${script_dir}")" == "bin" ]]; then
        base="$(dirname -- "${script_dir}")"
    else
        base="${CONFIG_BASE_DIRECTORY:-}"
    fi
    if [[ -z "${base}" || ! -f "${base}/config/global.conf" ]]; then
        printf '%s\n' "$(get_text mail.configuration-absent)" >&2
        exit 1
    fi
    export INSTALL_DIRECTORY="${base}"
    export CONFIG_BASE_DIRECTORY="${base}"
    read_language_file "${base}/config/global.conf"
    if ! declare -F get_text >/dev/null 2>&1; then
        printf '%s\n' "get_text absent" >&2
        exit 1
    fi
    # shellcheck disable=SC1091
    source "${base}/config/global.conf"
    if [[ -z "${WATCHDOG_MAIL:-}" && -r "${base}/config/secrets.conf" ]]; then
        # shellcheck disable=SC1091
        source "${base}/config/secrets.conf"
    fi
    export CONFIG_BASE_DIRECTORY="${base}"
    if [[ -z "${PROJECT_NAME:-}" ]]; then
        PROJECT_NAME="Liltress"
    fi
    export PROJECT_NAME
    send_sh="${base}/service/cron/watchdogs/send.sh"
    if [[ ! -f "${send_sh}" ]]; then
        printf '%s\n' "$(get_text mail.send-not-found)" >&2
        exit 1
    fi
    if [[ "${MAIL_ALERTS:-0}" != "1" ]]; then
        printf '%s\n' "$(get_text mail.alerts-e-mail-off)" >&2
        exit 1
    fi
    if [[ -z "${WATCHDOG_MAIL:-}" ]]; then
        printf '%s\n' "$(get_text mail.destinataire-absent)" >&2
        exit 1
    fi
    if ! command -v mail >/dev/null 2>&1; then
        printf '%s\n' "$(get_text mail.command-mail-absent)" >&2
        exit 1
    fi
    if [[ ! -f "${base}/template/${MAIL_TEMPLATE:-mail.html}" ]]; then
        printf '%s\n' "$(get_text mail.template-absent)" >&2
        exit 1
    fi
    export MAIL_TEMPLATE="${MAIL_TEMPLATE:-mail.html}"
    export MAIL_ALERTS
    export WATCHDOG_MAIL
    export TITLE="$(get_text mail.test.title)"
    export MODULE_NAME="$(get_text mail.test.module)"
    # One sample line is longer than the 800px floor.
    wide="$(printf 'X%.0s' {1..180})"
    export CONTENT="$(get_text mail.test.line-short)
$(get_text mail.test.line-wide "${wide}")
$(get_text mail.test.line-short)"
    export NOTE="$(get_text mail.test.note)"
    export NOTE_CMD="sudo bash ${base}/core/mail/mail-test.sh"
    err_file="$(mktemp)"
    if ! bash "${send_sh}" >/dev/null 2>"${err_file}"; then
        rm -f "${err_file}"
        printf '%s\n' "$(get_text mail.send-rejected)" >&2
        exit 1
    fi
    if grep -Eq 'Mail non envoyé|Mail not sent|Mail nicht gesendet|Mail no enviado' "${err_file}"; then
        rm -f "${err_file}"
        printf '%s\n' "$(get_text mail.send-rejected)" >&2
        exit 1
    fi
    rm -f "${err_file}"
    printf '%s\n' "$(get_text mail.message-of-attempt-sent)"
}

if [[ "$(basename -- "${script_dir}")" == "bin" ]]; then
    base="$(dirname -- "${script_dir}")"
else
    base="${CONFIG_BASE_DIRECTORY:-}"
fi
if [[ -n "${base}" && -f "${base}/config/global.conf" ]] && declare -F read_language_file >/dev/null 2>&1; then
    read_language_file "${base}/config/global.conf"
fi

if [[ "${EUID}" -ne 0 ]]; then
    if declare -F get_text >/dev/null 2>&1; then
        printf '%s\n' "$(get_text log.root-required)" >&2
    else
        printf '%s\n' "root required" >&2
    fi
    exit 1
fi

send_mail_test
