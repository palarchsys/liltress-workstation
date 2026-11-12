#!/usr/bin/env bash
# =============================================================================
# File       : script/config/apply-config.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================
# -----------------------------------------------------------------------------
# Purpose    : Write user.conf and secrets.conf, set MAIL_ALERTS in global.conf, then run the config check.
# Note       : The first argument is the destination root.
# Note       : The script does not call run.sh.
# -----------------------------------------------------------------------------

common="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"
# shellcheck disable=SC1090
source "${common}"

root="${1:-}"
if [[ -z "${root}" || ! -d "${root}" ]]; then
    fail_apply "Racine absente."
fi

asked_language="${LANGUAGE:-}"
asked_mail="${MAIL_ALERTS:-}"
asked_token="${UBUNTU_PRO_TOKEN:-}"
asked_login="${POSTFIX_SMTP_LOGIN:-}"
asked_address="${POSTFIX_MAIL_ADDRESS:-}"
asked_password="${POSTFIX_MAIL_PASSWORD:-}"
asked_smtp="${POSTFIX_MAIL_SMTP:-}"
asked_watchdog="${WATCHDOG_MAIL:-}"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
source "${script_dir}/../config-check.sh"

LANGUAGE="${asked_language}"
MAIL_ALERTS="${asked_mail:-0}"
UBUNTU_PRO_TOKEN="${asked_token}"
POSTFIX_SMTP_LOGIN="${asked_login}"
POSTFIX_MAIL_ADDRESS="${asked_address}"
POSTFIX_MAIL_PASSWORD="${asked_password}"
POSTFIX_MAIL_SMTP="${asked_smtp}"
WATCHDOG_MAIL="${asked_watchdog}"

if ! check_language "${LANGUAGE}"; then
    fail_apply "Langue inconnue."
fi

case "${MAIL_ALERTS}" in
    0)
        clear_mail
        ;;
    1)
        if ! check_app_password "${POSTFIX_MAIL_PASSWORD}"; then
            fail_apply "Mot de passe refusé."
        fi
        WATCHDOG_MAIL="${POSTFIX_MAIL_ADDRESS}"
        ;;
    *)
        fail_apply "Alerte inconnue."
        ;;
esac

if [[ ! -f "${root}/config/global.conf" ]]; then
    fail_apply "global.conf absent."
fi

mkdir -p "${root}/config"
write_user_config "${root}/config/user.conf"
write_secret_config "${root}/config/secrets.conf"
if ! write_mail_alerts "${root}/config/global.conf"; then
    fail_apply "Alerte refusée."
fi
unset INSTALL_DIRECTORY || true

if require_prepared_config "${root}"; then
    printf '%s\n' "Contrôle accepté."
    printf 'success\n'
    exit 0
fi

show_refusals
printf '%s\n' "Contrôle refusé."
printf 'error\n'
exit 1
