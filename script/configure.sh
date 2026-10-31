#!/usr/bin/env bash
# =============================================================================
# File       : script/configure.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

set -euo pipefail
INSTALL_WATCHER="${INSTALL_WATCHER:-BASH}"
export INSTALL_WATCHER

DIR_SCRIPT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${DIR_SCRIPT}/script/config-check.sh"
# shellcheck disable=SC1091
source "${DIR_SCRIPT}/core/lib.sh"

read_language_file "${DIR_SCRIPT}/config/global.conf"

show_usage() {
    printf '%s\n' "$(get_text configure.usage)"
}

read_secret() {
    local __out="$1"
    local char="" buf=""
    while true; do
        IFS= read -r -s -n 1 char || log_error        "${INSTALL_WATCHER}" "configure.input-interrupted"
        if [[ -z "${char}" || "${char}" == $'\n' ]]; then
            printf '\n' >&2
            break
        fi
        if [[ "${char}" == $'\177' || "${char}" == $'\b' ]]; then
            if [[ -n "${buf}" ]]; then
                buf="${buf%?}"
                printf '\b \b' >&2
            fi
            continue
        fi
        buf+="${char}"
        printf '*' >&2
    done
    printf -v "${__out}" '%s' "${buf}"
}

write_secret_line() {
    local label="$1" dest="$2" width="$3"
    printf '         \e[34m%*s\e[0m : ' "${width}" "${label}" >&2
    read_secret "${dest}"
}

prompt() {
    local __var="$1" __label="$2" __example="$3" __default="$4" __kind="$5" __hint="$6"
    local value="" confirm="" attempt current="" width
    current="${!__var:-}"
    [[ -n "${current}" ]] && __default="${current}"
    for attempt in 1 2 3; do
        echo ""
        if [[ "${__kind}" == "pro_token" || "${__kind}" == "secret" ]]; then
            width="${#__label}"
            [[ "${width}" -lt 12 ]] && width=12
            write_secret_line "${__label}" value "${width}"
            value="${value// /}"
            if [[ -z "${value}" && -n "${__default}" ]]; then
                value="${__default}"
            else
                write_secret_line "Confirmation" confirm "${width}"
                confirm="${confirm// /}"
                if [[ "${value}" != "${confirm}" ]]; then
                    echo ""
                    log_warn         "${INSTALL_WATCHER}" "configure.the-two-entries-differ"
                    continue
                fi
            fi
        else
            width="${#__label}"
            [[ "${width}" -lt 12 ]] && width=12
            printf '         \e[34m%*s\e[0m : ' "${width}" "${__label}" >&2
            IFS= read -r value || log_error        "${INSTALL_WATCHER}" "configure.input-interrupted"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
            if [[ -z "${value}" && -n "${__default}" ]]; then
                value="${__default}"
            fi
        fi
        local ok=0
        case "${__kind}" in
            pro_token) check_pro_token "${value}" && ok=1 ;;
            email) check_email "${value}" && ok=1 ;;
            secret) check_app_password "${value}" && ok=1 ;;
            smtp) check_smtp "${value}" && ok=1 ;;
            bool01) [[ "${value}" =~ ^[01]$ ]] && ok=1 ;;
            remote) check_drive_remote "${value}" && ok=1 ;;
            drive_path) check_drive_path "${value}" && ok=1 ;;
        esac
        if [[ "${ok}" == "1" ]]; then
            printf -v "${__var}" '%s' "${value}"
            return 0
        fi
        echo ""
        log_warn         "${INSTALL_WATCHER}" "configure.script.warn.2" "${__hint}"
    done
    log_error        "${INSTALL_WATCHER}" "configure.three-attempts-without-an-accepted-answer-exampl" "${__label}" "${__example}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_usage
    exit 0
fi

if [[ "${1:-}" == "--check" ]]; then
    log_info         "${INSTALL_WATCHER}" "configure.configuration-check"
    if require_prepared_config "${DIR_SCRIPT}"; then
        log_success      "${INSTALL_WATCHER}" "configure.configuration-conforms"
        exit 0
    fi
    exit 1
fi

if [[ -n "${1:-}" || $# -gt 0 ]]; then
    show_usage >&2
    exit 2
fi

if [[ ! -t 0 ]]; then
    if [[ ! -r /dev/tty ]]; then
        log_error        "${INSTALL_WATCHER}" "configure.no-terminal-for-the-questions-run-sudo-bash-lilt" "${DIR_SCRIPT}"
    fi
    exec </dev/tty
fi

require_root
clear

set_config_default

_saved_dir_set=0
_saved_dir=""
if [[ -n "${G_INSTALL_DIRECTORY+x}" ]]; then
    _saved_dir_set=1
    _saved_dir="${G_INSTALL_DIRECTORY}"
    unset G_INSTALL_DIRECTORY || true
fi
if [[ -f "${DIR_SCRIPT}/config/global.conf" ]]; then
    set +u
    # shellcheck disable=SC1091
    source "${DIR_SCRIPT}/config/global.conf"
    set -u
fi
if [[ "${_saved_dir_set}" == "1" ]]; then
    G_INSTALL_DIRECTORY="${_saved_dir}"
fi
unset _saved_dir _saved_dir_set
if [[ -f "${DIR_SCRIPT}/config/secrets.conf" ]]; then
    set +u
    # shellcheck disable=SC1091
    source "${DIR_SCRIPT}/config/secrets.conf"
    set -u
fi

ask_language

set_color_violet "═════════════════════════════════════════════════════════════════════════════════"
set_color_violet " Liltress Workstation — configuration                                               "
set_color_violet "═════════════════════════════════════════════════════════════════════════════════"

log_subtitle     "${INSTALL_WATCHER}" "configure.script.title"
log_info         "${INSTALL_WATCHER}" "configure.ubuntu-pro-token-url"
log_info         "${INSTALL_WATCHER}" "configure.letters-and-digits-without-spaces"
prompt G_UBUNTU_PRO_TOKEN \
    "Jeton Ubuntu Pro" \
    "C1abcdefghij1234567890" \
    "" \
    pro_token \
    "Lettres et chiffres seulement, entre 6 et 100, sans espace."

clear_mail() {
    G_POSTFIX_SMTP_LOGIN=""
    G_POSTFIX_MAIL_ADDRESS=""
    G_POSTFIX_MAIL_PASSWORD=""
    G_POSTFIX_MAIL_SMTP=""
    G_WATCHDOG_MAIL=""
}

check_smtp_probe() {
    local out="" rc=0 safe=""
    if ! command -v swaks >/dev/null 2>&1; then
        log_info         "${INSTALL_WATCHER}" "configure.installation-of-swaks-for-the-attempt-of-send"
        run_silent_apt   "${INSTALL_WATCHER}" "install -y swaks" "configure.script.error.5"
    fi
    out="$(swaks \
        --to "${G_POSTFIX_MAIL_ADDRESS}" \
        --from "${G_POSTFIX_MAIL_ADDRESS}" \
        --server "${G_POSTFIX_MAIL_SMTP}" \
        --auth LOGIN \
        --auth-user "${G_POSTFIX_SMTP_LOGIN}" \
        --auth-password "${G_POSTFIX_MAIL_PASSWORD}" \
        --tls \
        --timeout 25 \
        2>&1)" || rc=$?
    safe="${out//${G_POSTFIX_MAIL_PASSWORD}/$(get_text mail.redacted)}"
    if [[ "${rc}" -eq 0 ]] && printf '%s\n' "${safe}" | grep -qE '(^|[^0-9])250([^0-9]|$)'; then
        return 0
    fi
    echo ""
    log_warn         "${INSTALL_WATCHER}" "configure.the-data-email-are-not-good"
    printf '%s\n' "${safe}" | tail -n 12 >&2
    return 1
}

log_subtitle     "${INSTALL_WATCHER}" "configure.alerts-by-email"
log_info         "${INSTALL_WATCHER}" "configure.enable-the-alerts-by-emails-y-n"
while true; do
    echo ""
    printf "$(get_text configure.e-34m-s-e-0m)" 12 "Activer" >&2
    IFS= read -r mail_choice || log_error        "${INSTALL_WATCHER}" "configure.input-interrupted"
    case "${mail_choice}" in
        Y|y)
            clear_mail

            log_subtitle     "${INSTALL_WATCHER}" "configure.server-smtp"
            log_info         "${INSTALL_WATCHER}" "configure.form-host-port-for-example-smtp-mail-outlook-com"
            prompt G_POSTFIX_MAIL_SMTP \
                "$(get_text configure.server)" \
                "smtp-mail.outlook.com:587" \
                "" \
                smtp \
                "$(get_text configure.enter-the-server-and-the-port-without-brackets-e)"

            log_subtitle     "${INSTALL_WATCHER}" "configure.login-smtp"
            log_info         "${INSTALL_WATCHER}" "configure.address-email-serving-of-login"
            prompt G_POSTFIX_SMTP_LOGIN \
                "$(get_text configure.login)" \
                "$(get_text configure.toi-exemple-com)" \
                "" \
                email \
                "$(get_text configure.enter-the-address-email-of-the-account-smtp)"

            log_subtitle     "${INSTALL_WATCHER}" "configure.password-of-application"
            log_info         "${INSTALL_WATCHER}" "configure.spaces-removed-the-line-following-confirms"
            prompt G_POSTFIX_MAIL_PASSWORD \
                "$(get_text configure.password)" \
                "mot-de-passe-application" \
                "" \
                secret \
                "$(get_text configure.password-of-application-at-least-8-characters-wi)"

            log_subtitle     "${INSTALL_WATCHER}" "configure.sender"
            log_info         "${INSTALL_WATCHER}" "configure.the-alerts-leave-toward-this-same-address"
            prompt G_POSTFIX_MAIL_ADDRESS \
                "$(get_text configure.from)" \
                "$(get_text configure.toi-exemple-com)" \
                "" \
                email \
                "$(get_text configure.enter-the-address-email-sender)"
            G_WATCHDOG_MAIL="${G_POSTFIX_MAIL_ADDRESS}"

            log_subtitle     "${INSTALL_WATCHER}" "configure.attempt-of-send"
            log_info         "${INSTALL_WATCHER}" "configure.attempt-of-send-swaks-checks-server-login-passwo"
            if check_smtp_probe; then
                G_MAIL_ALERTS=1
                log_success      "${INSTALL_WATCHER}" "configure.attempt-of-send-accepted"
                break
            fi
            clear_mail
            log_info         "${INSTALL_WATCHER}" "configure.return-to-the-choice-of-the-alerts"
            ;;
        N|n|non)
            log_info         "${INSTALL_WATCHER}" "configure.cutoff-of-the-alerts-email"
            clear_mail
            G_MAIL_ALERTS=0
            log_success      "${INSTALL_WATCHER}" "configure.alerts-email-off-the-checks-will-start-without-s-2"
            break
            ;;
        *)
            log_warn         "${INSTALL_WATCHER}" "log.answer-y-or-n"
            ;;
    esac
done

clear_drive() {
    local base
    G_RCLONE_ALERTS=0
    base="${G_CONFIG_BASE_DIRECTORY:-/opt/liltress-workstation}"
    rm -f "${base}/cron/rclone.conf"
}

ask_drive_alert() {
    local choice="" base config old_umask
    base="${G_CONFIG_BASE_DIRECTORY:-/opt/liltress-workstation}"
    log_subtitle     "${INSTALL_WATCHER}" "configure.alerts-toward-google-drive"
    log_info         "${INSTALL_WATCHER}" "configure.enable-the-send-of-the-alerts-toward-google-driv"
    while true; do
        echo ""
        printf "$(get_text configure.e-34m-s-e-0m)" 12 "Drive" >&2
        IFS= read -r choice || log_error        "${INSTALL_WATCHER}" "configure.input-interrupted"
        case "${choice}" in
            Y|y)
                : "${G_RCLONE_REMOTE:=gdrive}"
                : "${G_RCLONE_PATH:=liltress-alerts}"
                prompt G_RCLONE_REMOTE \
                    "Distant" \
                    "gdrive" \
                    "${G_RCLONE_REMOTE}" \
                    remote \
                    "Lettres, chiffres ou tiret, de 1 à 32 caractères."
                prompt G_RCLONE_PATH \
                    "Dossier" \
                    "liltress-alerts" \
                    "${G_RCLONE_PATH}" \
                    drive_path \
                    "Dossier distant, sans .. et sans chemin local."
                if ! command -v rclone >/dev/null 2>&1; then
                    log_info         "${INSTALL_WATCHER}" "configure.installation-of-rclone"
                    run_silent_apt   "${INSTALL_WATCHER}" "install --no-install-recommends -y rclone" "configure.script.error.8"
                fi
                config="${base}/cron/rclone.conf"
                mkdir -p "${base}/cron"
                rm -f "${config}"
                old_umask="$(umask)"
                umask 077
                if ! RCLONE_CONFIG="${config}" rclone config create "${G_RCLONE_REMOTE}" drive; then
                    umask "${old_umask}"
                    rm -f "${config}"
                    log_warn         "${INSTALL_WATCHER}" "configure.the-configuration-rclone-was-rejected"
                    log_info         "${INSTALL_WATCHER}" "configure.return-to-the-choice-google-drive"
                    continue
                fi
                umask "${old_umask}"
                if [[ ! -f "${config}" ]]; then
                    log_warn         "${INSTALL_WATCHER}" "configure.the-configuration-rclone-was-rejected"
                    log_info         "${INSTALL_WATCHER}" "configure.return-to-the-choice-google-drive"
                    continue
                fi
                chmod 600 "${config}"
                if check_drive_probe "${G_RCLONE_REMOTE}" "${G_RCLONE_PATH}" "${config}"; then
                    G_RCLONE_ALERTS=1
                    log_success      "${INSTALL_WATCHER}" "configure.attempt-google-drive-accepted"
                    return 0
                fi
                rm -f "${config}"
                log_warn         "${INSTALL_WATCHER}" "configure.the-attempt-google-drive-was-denied"
                log_info         "${INSTALL_WATCHER}" "configure.return-to-the-choice-google-drive"
                ;;
            N|n|non)
                clear_drive
                log_success      "${INSTALL_WATCHER}" "configure.send-google-drive-cut"
                return 0
                ;;
            *)
                log_warn         "${INSTALL_WATCHER}" "log.answer-y-or-n"
                ;;
        esac
    done
}

ask_drive_alert

log_subtitle     "${INSTALL_WATCHER}" "configure.mode-test"
log_info         "${INSTALL_WATCHER}" "configure.1-no-removal-0-question-at-the-end-of-installati"
log_info         "${INSTALL_WATCHER}" "configure.entry-keeps-the-value-in-progress-1-by-default"
prompt G_MODE_TEST \
    "$(get_text configure.mode-test)" \
    "1" \
    "${G_MODE_TEST:-1}" \
    bool01 \
    "$(get_text configure.enter-0-or-1)"

log_info         "${INSTALL_WATCHER}" "configure.record-of-the-configuration"
mkdir -p "${DIR_SCRIPT}/config"
write_global_config "${DIR_SCRIPT}/config/global.conf"
write_secret_config "${DIR_SCRIPT}/config/secrets.conf"

if ! require_prepared_config "${DIR_SCRIPT}"; then
    log_error        "${INSTALL_WATCHER}" "configure.the-files-written-pass-not-the-check"
fi

log_success      "${INSTALL_WATCHER}" "configure.configuration-saved"
exec bash "${DIR_SCRIPT}/script/run.sh"
echo ""
