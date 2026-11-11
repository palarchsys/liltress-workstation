#!/usr/bin/env bash
# =============================================================================
# File       : script/configure.sh
# Updated at : 2026-11-11
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

show_usage() {
    printf '%s\n' "$(get_text configure.usage.workstation)"
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

print_field() {
    local label="$1"
    local width="${#label}"
    [[ "${width}" -lt 12 ]] && width=12
    step_flush_branch
    if [[ "${SECTION_OPEN:-0}" == "1" ]]; then
        printf '%s' "$(step_bar)" >&2
    else
        printf '         ' >&2
    fi
    printf '\e[34m%*s\e[0m : ' "${width}" "${label}" >&2
}

write_secret_line() {
    local label="$1" dest="$2"
    print_field "${label}"
    read_secret "${dest}"
}

prompt() {
    local __var="$1" __label="$2" __example="$3" __default="$4" __kind="$5" __hint="$6"
    local value="" confirm="" attempt current=""
    current="${!__var:-}"
    [[ -n "${current}" ]] && __default="${current}"
    for attempt in 1 2 3; do
        if [[ "${SECTION_OPEN:-0}" != "1" ]]; then
            echo "" >&2
        fi
        if [[ "${__kind}" == "pro_token" || "${__kind}" == "secret" ]]; then
            write_secret_line "${__label}" value
            value="${value// /}"
            if [[ -z "${value}" && -n "${__default}" ]]; then
                value="${__default}"
            else
                write_secret_line "Confirmation" confirm
                confirm="${confirm// /}"
                if [[ "${value}" != "${confirm}" ]]; then
                    echo "" >&2
                    log_warn         "${INSTALL_WATCHER}" "configure.the-two-entries-differ"
                    continue
                fi
            fi
        else
            print_field "${__label}"
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
    read_language_file "${DIR_SCRIPT}/config/global.conf"
    show_usage
    exit 0
fi

if [[ "${1:-}" == "--check" ]]; then
    read_language_file "${DIR_SCRIPT}/config/global.conf"
    log_info         "${INSTALL_WATCHER}" "configure.configuration-check"
    if require_prepared_config "${DIR_SCRIPT}"; then
        log_success      "${INSTALL_WATCHER}" "configure.configuration-conforms"
        exit 0
    fi
    exit 1
fi

if [[ -n "${1:-}" || $# -gt 0 ]]; then
    read_language_file "${DIR_SCRIPT}/config/global.conf"
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

ask_language
asked_language="${LANGUAGE}"

set_config_default

_saved_dir_set=0
_saved_dir=""
if [[ -n "${INSTALL_DIRECTORY+x}" ]]; then
    _saved_dir_set=1
    _saved_dir="${INSTALL_DIRECTORY}"
    unset INSTALL_DIRECTORY || true
fi
if [[ -f "${DIR_SCRIPT}/config/global.conf" ]]; then
    set +u
    # shellcheck disable=SC1091
    source "${DIR_SCRIPT}/config/global.conf"
    set -u
fi
if [[ -f "${DIR_SCRIPT}/config/user.conf" ]]; then
    set +u
    # shellcheck disable=SC1091
    source "${DIR_SCRIPT}/config/user.conf"
    set -u
fi
if [[ "${_saved_dir_set}" == "1" ]]; then
    INSTALL_DIRECTORY="${_saved_dir}"
fi
unset _saved_dir _saved_dir_set
LANGUAGE="${asked_language}"
export LANGUAGE
TEXT_READY=0
load_text "${LANGUAGE}"
unset asked_language
if [[ -f "${DIR_SCRIPT}/config/secrets.conf" ]]; then
    set +u
    # shellcheck disable=SC1091
    source "${DIR_SCRIPT}/config/secrets.conf"
    set -u
fi

show_title_box "${PROJECT_NAME}"

set_step_visible "$(get_text configure.script.title)"
open_step_tree "$(get_text configure.script.title)"
log_info         "${INSTALL_WATCHER}" "configure.ubuntu-pro-token-url"
log_info         "${INSTALL_WATCHER}" "configure.letters-and-digits-without-spaces"
prompt UBUNTU_PRO_TOKEN \
    "Jeton Ubuntu Pro" \
    "C1abcdefghij1234567890" \
    "" \
    pro_token \
    "Lettres et chiffres seulement, entre 6 et 100, sans espace."
log_success      "${INSTALL_WATCHER}" "configure.ubuntu-pro-accepted"
close_step_tree

clear_mail() {
    POSTFIX_SMTP_LOGIN=""
    POSTFIX_MAIL_ADDRESS=""
    POSTFIX_MAIL_PASSWORD=""
    POSTFIX_MAIL_SMTP=""
    WATCHDOG_MAIL=""
}

check_smtp_probe() {
    local out="" rc=0 safe=""
    if ! command -v swaks >/dev/null 2>&1; then
        log_info         "${INSTALL_WATCHER}" "configure.installation-of-swaks-for-the-attempt-of-send"
        run_silent_apt   "${INSTALL_WATCHER}" "install -y swaks" "configure.script.error.5"
    fi
    out="$(swaks \
        --to "${POSTFIX_MAIL_ADDRESS}" \
        --from "${POSTFIX_MAIL_ADDRESS}" \
        --server "${POSTFIX_MAIL_SMTP}" \
        --auth LOGIN \
        --auth-user "${POSTFIX_SMTP_LOGIN}" \
        --auth-password "${POSTFIX_MAIL_PASSWORD}" \
        --tls \
        --timeout 25 \
        2>&1)" || rc=$?
    safe="${out//${POSTFIX_MAIL_PASSWORD}/$(get_text mail.redacted)}"
    if [[ "${rc}" -eq 0 ]] && printf '%s\n' "${safe}" | grep -qE '(^|[^0-9])250([^0-9]|$)'; then
        return 0
    fi
    echo ""
    log_warn         "${INSTALL_WATCHER}" "configure.the-data-email-are-not-good"
    printf '%s\n' "${safe}" | tail -n 12 >&2
    return 1
}

set_step_visible "$(get_text configure.enable-the-alerts-by-emails-y-n)"
open_step_tree "$(get_text configure.enable-the-alerts-by-emails-y-n)"
log_info         "${INSTALL_WATCHER}" "configure.enable-the-alerts-by-emails-y-n"
while true; do
    print_field "Activer"
    IFS= read -r mail_choice || log_error        "${INSTALL_WATCHER}" "configure.input-interrupted"
    case "${mail_choice}" in
        Y|y)
            clear_mail

            log_info         "${INSTALL_WATCHER}" "configure.form-host-port-for-example-smtp-mail-outlook-com"
            prompt POSTFIX_MAIL_SMTP \
                "$(get_text configure.server)" \
                "smtp-mail.outlook.com:587" \
                "" \
                smtp \
                "$(get_text configure.enter-the-server-and-the-port-without-brackets-e)"

            log_info         "${INSTALL_WATCHER}" "configure.address-email-serving-of-login"
            prompt POSTFIX_SMTP_LOGIN \
                "$(get_text configure.login)" \
                "$(get_text configure.toi-exemple-com)" \
                "" \
                email \
                "$(get_text configure.enter-the-address-email-of-the-account-smtp)"

            log_info         "${INSTALL_WATCHER}" "configure.spaces-removed-the-line-following-confirms"
            prompt POSTFIX_MAIL_PASSWORD \
                "$(get_text configure.password)" \
                "mot-de-passe-application" \
                "" \
                secret \
                "$(get_text configure.password-of-application-at-least-8-characters-wi)"

            log_info         "${INSTALL_WATCHER}" "configure.the-alerts-leave-toward-this-same-address"
            prompt POSTFIX_MAIL_ADDRESS \
                "$(get_text configure.from)" \
                "$(get_text configure.toi-exemple-com)" \
                "" \
                email \
                "$(get_text configure.enter-the-address-email-sender)"
            WATCHDOG_MAIL="${POSTFIX_MAIL_ADDRESS}"

            log_info         "${INSTALL_WATCHER}" "configure.attempt-of-send-swaks-checks-server-login-passwo"
            if check_smtp_probe; then
                MAIL_ALERTS=1
                log_success      "${INSTALL_WATCHER}" "configure.attempt-of-send-accepted"
                break
            fi
            clear_mail
            log_info         "${INSTALL_WATCHER}" "configure.return-to-the-choice-of-the-alerts"
            ;;
        N|n|non)
            log_info         "${INSTALL_WATCHER}" "configure.cutoff-of-the-alerts-email"
            clear_mail
            MAIL_ALERTS=0
            log_success      "${INSTALL_WATCHER}" "configure.alerts-email-off-the-checks-will-start-without-s-2"
            break
            ;;
        *)
            log_warn         "${INSTALL_WATCHER}" "log.answer-y-or-n"
            ;;
    esac
done
close_step_tree

set_step_visible "$(get_text configure.record-of-the-configuration)"
open_step_tree "$(get_text configure.record-of-the-configuration)"
log_info         "${INSTALL_WATCHER}" "configure.record-of-the-configuration"
mkdir -p "${DIR_SCRIPT}/config"
write_user_config "${DIR_SCRIPT}/config/user.conf"
write_secret_config "${DIR_SCRIPT}/config/secrets.conf"
write_mail_alerts "${DIR_SCRIPT}/config/global.conf"

if ! require_prepared_config "${DIR_SCRIPT}"; then
    log_error        "${INSTALL_WATCHER}" "configure.the-files-written-pass-not-the-check"
fi

log_success      "${INSTALL_WATCHER}" "configure.configuration-saved"
close_step_tree
show_section_close
exec bash "${DIR_SCRIPT}/script/run.sh"
