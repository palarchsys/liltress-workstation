#!/usr/bin/env bash
# =============================================================================
# File       : core/mail-test.sh
# Updated at : 2026-10-31
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
    "${script_dir}/../core/log.sh" \
    "${script_dir}/../src/core/log.sh" \
    "${G_CONFIG_BASE_DIRECTORY:-}/src/core/log.sh" \
    "${G_INSTALL_DIRECTORY:-}/core/log.sh" \
    "${G_INSTALL_DIRECTORY:-}/src/core/log.sh"
do
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
        # shellcheck disable=SC1090
        source "${candidate}"
        break
    fi
done

send_mail_test() {
    local script_dir base send_sh wide err_file
    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    if [[ "$(basename -- "${script_dir}")" == "bin" ]]; then
        base="$(dirname -- "${script_dir}")"
    else
        base="${G_CONFIG_BASE_DIRECTORY:-}"
    fi
    if [[ -z "${base}" || ! -f "${base}/config/global.conf" ]]; then
        printf '%s\n' "$(get_text mail.configuration-absent)" >&2
        exit 1
    fi
    export G_INSTALL_DIRECTORY="${base}"
    export G_CONFIG_BASE_DIRECTORY="${base}"
    read_language_file "${base}/config/global.conf"
    # shellcheck disable=SC1091
    source "${base}/config/global.conf"
    if [[ -f "${base}/cron/mail.conf" ]]; then
        # shellcheck disable=SC1091
        source "${base}/cron/mail.conf"
    fi
    if [[ -f "${base}/cron/bin/watchdog.conf" ]]; then
        # shellcheck disable=SC1091
        source "${base}/cron/bin/watchdog.conf"
    fi
    if [[ -z "${G_WATCHDOG_MAIL:-}" && -f "${base}/config/secrets.conf" ]]; then
        # shellcheck disable=SC1091
        source "${base}/config/secrets.conf"
    fi
    export G_CONFIG_BASE_DIRECTORY="${base}"
    if [[ -z "${G_PROJECT_NAME:-}" ]]; then
        G_PROJECT_NAME="Liltress"
    fi
    export G_PROJECT_NAME
    send_sh="${base}/cron/bin/send.sh"
    if [[ ! -f "${send_sh}" ]]; then
        printf '%s\n' "$(get_text mail.send-not-found)" >&2
        exit 1
    fi
    if [[ "${G_MAIL_ALERTS:-0}" != "1" ]]; then
        printf '%s\n' "$(get_text mail.alerts-e-mail-off)" >&2
        exit 1
    fi
    if [[ -z "${G_WATCHDOG_MAIL:-}" ]]; then
        printf '%s\n' "$(get_text mail.destinataire-absent)" >&2
        exit 1
    fi
    if ! command -v mail >/dev/null 2>&1; then
        printf '%s\n' "$(get_text mail.command-mail-absent)" >&2
        exit 1
    fi
    if [[ ! -f "${base}/cron/bin/${G_MAIL_TEMPLATE:-mail.html}" ]]; then
        printf '%s\n' "$(get_text mail.template-absent)" >&2
        exit 1
    fi
    export G_MAIL_TEMPLATE="${G_MAIL_TEMPLATE:-mail.html}"
    export G_MAIL_ALERTS
    export G_WATCHDOG_MAIL
    export TITLE="$(get_text mail.test.title)"
    export MODULE_NAME="$(get_text mail.test.module)"
    # One sample line is longer than the 800px floor.
    wide="$(printf 'X%.0s' {1..180})"
    export CONTENT="$(get_text mail.test.line-short)
$(get_text mail.test.line-wide "${wide}")
$(get_text mail.test.line-short)"
    export NOTE="$(get_text mail.test.note)"
    export NOTE_CMD="sudo bash ${base}/bin/mail-test.sh"
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
    base="${G_CONFIG_BASE_DIRECTORY:-}"
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
