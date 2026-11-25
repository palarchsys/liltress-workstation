#!/usr/bin/env bash
# =============================================================================
# File       : script/configure.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Ask the workstation settings and record them.
# Note       : An interrupted entry stops the command.
# Note       : Mail alerts stay off when the answer is N|n|non.
# -----------------------------------------------------------------------------


workstation_configure_01_run_01_check() {
    set -euo pipefail
    INSTALL_WATCHER="${INSTALL_WATCHER:-BASH}"
    export INSTALL_WATCHER

    DIR_SCRIPT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
    # shellcheck disable=SC1091
    source "${DIR_SCRIPT}/script/config-check.sh"
    # shellcheck disable=SC1091
    source "${DIR_SCRIPT}/script/config/common.sh"
    # shellcheck disable=SC1091
    source "${DIR_SCRIPT}/core/boot/lib.sh"

}

show_usage() {
    printf '%s\n' "$(get_text configure.usage.workstation)"
}

# A secret is typed twice, in clear. An empty entry keeps the saved text.
read_prompt_pair() {
    local label="$1"
    local fallback="$2"
    local secret="" confirm=""
    ask_line "${label}" secret || log_error "${INSTALL_WATCHER}" "configure.input-interrupted"
    secret="${secret// /}"
    if [[ -z "${secret}" && -n "${fallback}" ]]; then
        value="${fallback}"
        return 0
    fi
    ask_line "$(get_text configure.field.confirm)" confirm || log_error "${INSTALL_WATCHER}" "configure.input-interrupted"
    confirm="${confirm// /}"
    if [[ "${secret}" != "${confirm}" ]]; then
        log_warn "${INSTALL_WATCHER}" "configure.the-two-entries-differ"
        return 1
    fi
    value="${secret}"
    return 0
}

# Spaces at the ends are removed. An empty entry keeps the saved text.
read_prompt_line() {
    local label="$1"
    local fallback="$2"
    ask_line "${label}" value || log_error "${INSTALL_WATCHER}" "configure.input-interrupted"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if [[ -z "${value}" && -n "${fallback}" ]]; then
        value="${fallback}"
    fi
}

# Each kind accepts one shape.
check_prompt_value() {
    local kind="$1"
    local entry="$2"
    case "${kind}" in
        pro_token) check_pro_token "${entry}" ;;
        tailscale) [[ "${entry}" =~ ^tskey-auth-[A-Za-z0-9_-]{10,200}$ ]] ;;
        user) [[ "${entry}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] ;;
        ssh_port) check_port "${entry}" 1024 65535 ;;
        email) check_email "${entry}" ;;
        secret) check_app_password "${entry}" ;;
        smtp) check_smtp "${entry}" ;;
        bool01) [[ "${entry}" =~ ^[01]$ ]] ;;
        *) return 1 ;;
    esac
}

# These kinds are typed twice, in clear.
prompt_needs_confirm() {
    case "$1" in
        pro_token | secret | tailscale) return 0 ;;
    esac
    return 1
}

prompt() {
    local field_name="$1" field_label="$2" field_example="$3" field_default="$4" field_kind="$5" field_hint="$6"
    local value="" attempt current=""
    current="${!field_name:-}"
    [[ -n "${current}" ]] && field_default="${current}"
    for attempt in 1 2 3; do
        if prompt_needs_confirm "${field_kind}"; then
            read_prompt_pair "${field_label}" "${field_default}" || continue
        else
            read_prompt_line "${field_label}" "${field_default}"
        fi
        if check_prompt_value "${field_kind}" "${value}"; then
            printf -v "${field_name}" '%s' "${value}"
            return 0
        fi
        echo ""
        log_warn "${INSTALL_WATCHER}" "configure.script.warn.2" "${field_hint}"
    done
    log_error "${INSTALL_WATCHER}" "configure.three-attempts-without-an-accepted-answer-exampl" "${field_label}" "${field_example}"
}

workstation_configure_01_run_02_read() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        read_language_file "${DIR_SCRIPT}/config/global.conf"
        show_usage
        exit 0
    fi

}

workstation_configure_01_run_03_read() {
    if [[ -n "${1:-}" || $# -gt 0 ]]; then
        read_language_file "${DIR_SCRIPT}/config/global.conf"
        show_usage >&2
        exit 2
    fi

    if [[ ! -t 0 ]]; then
        if [[ ! -r /dev/tty ]]; then
            log_error "${INSTALL_WATCHER}" "configure.no-terminal-for-the-questions-run-sudo-bash-lilt" "${DIR_SCRIPT}"
        fi
        exec </dev/tty
    fi

    require_root
    set_step_visible "$(get_text install.configuration.title)"
    begin_step_tree "script/configure.sh"

}

workstation_configure_01_run_04_load() {
    asked_language="${LANGUAGE}"

    set_config_default

    saved_directory_set=0
    saved_directory=""
    if [[ -n "${INSTALL_DIRECTORY+x}" ]]; then
        saved_directory_set=1
        saved_directory="${INSTALL_DIRECTORY}"
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
    if [[ "${saved_directory_set}" == "1" ]]; then
        INSTALL_DIRECTORY="${saved_directory}"
    fi
    unset saved_directory saved_directory_set
    LANGUAGE="${asked_language}"
    export LANGUAGE
    TEXT_READY=0
    load_text "${LANGUAGE}"
    unset asked_language
}

check_smtp_probe() {
    local out="" rc=0 safe=""
    if ! command -v swaks >/dev/null 2>&1; then
        log_info "${INSTALL_WATCHER}" "configure.installation-of-swaks-for-the-attempt-of-send"
        run_silent_apt "${INSTALL_WATCHER}" "install -y swaks" "configure.script.error.5"
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
    log_warn "${INSTALL_WATCHER}" "configure.the-data-email-are-not-good"
    printf '%s\n' "${safe}" | tail -n 12 >&2
    return 1
}

ask_smtp_values() {
    clear_mail
    ask_smtp_host
    ask_smtp_login
    ask_smtp_secret
    ask_smtp_from
    WATCHDOG_MAIL="${POSTFIX_MAIL_ADDRESS}"
    log_info "${INSTALL_WATCHER}" "configure.attempt-of-send-swaks-checks-server-login-passwo"
    if check_smtp_probe; then
        MAIL_ALERTS=1
        log_success "${INSTALL_WATCHER}" "configure.attempt-of-send-accepted"
        return 0
    fi
    clear_mail
    log_info "${INSTALL_WATCHER}" "configure.return-to-the-choice-of-the-alerts"
    return 1
}

workstation_configure_01_run_06_get() {
    set_step_visible "$(get_text configure.enable-the-alerts-by-emails-y-n)"
    begin_step_tree "$(get_text configure.enable-the-alerts-by-emails-y-n)"
    log_info "${INSTALL_WATCHER}" "configure.enable-the-alerts-by-emails-y-n"
    mail_choice=""
    while true; do
        ask_line "$(get_text configure.enable-the-alerts-by-emails-y-n)" mail_choice || log_error "${INSTALL_WATCHER}" "configure.input-interrupted"
        case "${mail_choice}" in
            Y | y)
                if ask_smtp_values; then
                    break
                fi
                ;;
            N | n | non)
                log_info "${INSTALL_WATCHER}" "configure.cutoff-of-the-alerts-email"
                clear_mail
                MAIL_ALERTS=0
                log_success "${INSTALL_WATCHER}" "configure.alerts-email-off-the-checks-will-start-without-s-2"
                break
                ;;
            *)
                log_warn "${INSTALL_WATCHER}" "log.answer-y-or-n"
                ;;
        esac
    done
    finish_step_tree

    set_step_visible "$(get_text configure.record-of-the-configuration)"
    begin_step_tree "$(get_text configure.record-of-the-configuration)"
    log_info "${INSTALL_WATCHER}" "configure.record-of-the-configuration"
    mkdir -p "${DIR_SCRIPT}/config"
    write_user_config "${DIR_SCRIPT}/config/user.conf"
    write_secret_config "${DIR_SCRIPT}/config/secrets.conf"
    write_mail_alerts "${DIR_SCRIPT}/config/global.conf"

}

workstation_configure_01_run_07_pass() {
    if ! require_prepared_config "${DIR_SCRIPT}"; then
        log_error "${INSTALL_WATCHER}" "configure.the-files-written-pass-not-the-check"
    fi

    log_success "${INSTALL_WATCHER}" "configure.configuration-saved"
    finish_step_tree
    show_section_close
    exec bash "${DIR_SCRIPT}/script/run.sh"
}
workstation_configure_01_run_01_check "$@"
workstation_configure_01_run_02_read "$@"
if [[ "${1:-}" == "--check" ]]; then
    read_language_file "${DIR_SCRIPT}/config/global.conf"
    log_info "${INSTALL_WATCHER}" "configure.configuration-check"
    if require_prepared_config "${DIR_SCRIPT}"; then
        log_success "${INSTALL_WATCHER}" "configure.configuration-conforms"
        exit 0
    fi
    exit 1
fi
workstation_configure_01_run_03_read "$@"
ask_language

workstation_configure_01_run_05_prompt() {
    if [[ -f "${DIR_SCRIPT}/config/secrets.conf" ]]; then
        set +u
        # shellcheck disable=SC1091
        source "${DIR_SCRIPT}/config/secrets.conf"
        set -u
    fi

    log_info "${INSTALL_WATCHER}" "configure.ubuntu-pro-token-url"
    log_info "${INSTALL_WATCHER}" "configure.letters-and-digits-without-spaces"
    prompt UBUNTU_PRO_TOKEN \
        "$(get_text configure.field.pro-token)" \
        "C1abcdefghij1234567890" \
        "" \
        pro_token \
        "$(get_text configure.hint.pro-token)"
    log_success "${INSTALL_WATCHER}" "configure.ubuntu-pro-accepted"
    prompt TAILSCALE_AUTH_KEY \
        "$(get_text configure.field.tailscale)" \
        "tskey-auth-reusable" \
        "" \
        tailscale \
        "$(get_text configure.hint.tailscale)"
    log_success "${INSTALL_WATCHER}" "configure.ubuntu-pro-accepted"
    prompt SSH_USER "$(get_text configure.field.ssh-user)" "drawbridge" "${SSH_USER:-drawbridge}" user "$(get_text configure.hint.ssh-user)"
    prompt SSH_GROUP "$(get_text configure.field.ssh-group)" "drawbridge" "${SSH_GROUP:-drawbridge}" user "$(get_text configure.hint.ssh-group)"
    prompt SSH_PORT "$(get_text configure.field.ssh-port)" "2501" "${SSH_PORT:-2501}" ssh_port "$(get_text configure.hint.ssh-port)"
    finish_step_tree

}

ask_smtp_host() {
    log_info "${INSTALL_WATCHER}" "configure.form-host-port-for-example-smtp-mail-outlook-com"
    prompt POSTFIX_MAIL_SMTP \
        "$(get_text configure.server)" \
        "smtp-mail.outlook.com:587" \
        "" \
        smtp \
        "$(get_text configure.enter-the-server-and-the-port-without-brackets-e)"
}

ask_smtp_login() {
    log_info "${INSTALL_WATCHER}" "configure.address-email-serving-of-login"
    prompt POSTFIX_SMTP_LOGIN \
        "$(get_text configure.login)" \
        "$(get_text configure.toi-exemple-com)" \
        "" \
        email \
        "$(get_text configure.enter-the-address-email-of-the-account-smtp)"
}

ask_smtp_secret() {
    log_info "${INSTALL_WATCHER}" "configure.spaces-removed-the-line-following-confirms"
    prompt POSTFIX_MAIL_PASSWORD \
        "$(get_text configure.password)" \
        "mot-de-passe-application" \
        "" \
        secret \
        "$(get_text configure.password-of-application-at-least-8-characters-wi)"
}

ask_smtp_from() {
    log_info "${INSTALL_WATCHER}" "configure.the-alerts-leave-toward-this-same-address"
    prompt POSTFIX_MAIL_ADDRESS \
        "$(get_text configure.from)" \
        "$(get_text configure.toi-exemple-com)" \
        "" \
        email \
        "$(get_text configure.enter-the-address-email-sender)"
}
workstation_configure_01_run_04_load "$@"
workstation_configure_01_run_05_prompt "$@"
workstation_configure_01_run_06_get "$@"
workstation_configure_01_run_07_pass "$@"
