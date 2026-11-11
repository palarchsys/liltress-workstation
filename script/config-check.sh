#!/usr/bin/env bash
# =============================================================================
# File       : script/config-check.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

PRODUCT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${PRODUCT_ROOT}/../share/core/bootstrap.sh" ]]; then
    # shellcheck disable=SC1091
    source "${PRODUCT_ROOT}/../share/core/bootstrap.sh"
elif [[ -f "${PRODUCT_ROOT}/core/bootstrap.sh" ]]; then
    # shellcheck disable=SC1091
    source "${PRODUCT_ROOT}/core/bootstrap.sh"
else
    printf 'bootstrap core not found from %s\n' "${PRODUCT_ROOT}" >&2
    exit 1
fi
source_core config-validators.sh
source_core log.sh

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '%s\n' "$(get_text configure.use-liltress-configures-check-n)" >&2
    exit 1
fi

CONFIG_ERRORS=()

check_pro_token() {
    [[ "$1" =~ ^[A-Za-z0-9]{6,100}$ ]]
}

set_config_default() {
    : "${PROJECT_NAME:=Liltress Workstation}"
    : "${PROJECT_SLUG:=liltress-workstation}"
    : "${PROJECT_VERSION:=0.2}"
    : "${LYNIS_MIN_SCORE:=80}"
    : "${SSH_BANNER_PATH:=/etc/ssh/sshd_banner}"
    : "${SSH_SERVICE_NAME:=ssh}"
    : "${SSH_MAX_AUTH_TRIES:=4}"
    : "${SSH_CLIENT_ALIVE_INTERVAL:=300}"
    : "${SSH_CLIENT_ALIVE_COUNT_MAX:=2}"
    : "${SSH_LOGIN_GRACE_TIME:=30}"
    : "${PAM_PASSWORD_MIN_LENGTH:=12}"
    : "${FAILLOCK_DENY:=8}"
    : "${FAILLOCK_UNLOCK:=600}"
    : "${FAILLOCK_FAIL_INTERVAL:=900}"
    : "${WATCHDOG_CPU_LIMIT:=50}"
    : "${WATCHDOG_LIMIT_NICE:=19}"
    : "${WATCHDOG_LIMIT_IO_NICE:=3}"
    : "${UBUNTU_PRO_TOKEN:=}"
    : "${MAIL_ALERTS:=0}"
    : "${MAIL_TEMPLATE:=mail.html}"
    : "${POSTFIX_SMTP_LOGIN:=}"
    : "${POSTFIX_MAIL_ADDRESS:=}"
    : "${POSTFIX_MAIL_PASSWORD:=}"
    : "${POSTFIX_MAIL_SMTP:=}"
    : "${WATCHDOG_MAIL:=}"
    if [[ -z "${BANNER_MESSAGE:-}" ]]; then
        BANNER_MESSAGE="***********************************************************************
*                                                                     *
* This system is the property of its owner.                           *
* Unauthorized access is strictly prohibited and will be prosecuted.  *
*                                                                     *
* All access, activities, and communications on this system are       *
* monitored, recorded, and may be disclosed to authorized parties.    *
* By proceeding, you consent to this monitoring.                      *
*                                                                     *
* Any unauthorized use may result in civil and/or criminal penalties  *
* under applicable laws.                                              *
*                                                                     *
* Unauthorized users: Disconnect immediately.                         *
*                                                                     *
***********************************************************************"
    fi
}

write_global_config() {
    local dest="$1"
    cat > "${dest}" << EOF
# =============================================================================
# File       : config/global.conf
# Updated at : 2026-11-05
# Creator    : palarchsys
# =============================================================================

CONFIG_PREPARED=1

PROJECT_NAME="${PROJECT_NAME}"
PROJECT_VERSION="${PROJECT_VERSION}"

CONFIG_BASE_DIRECTORY="/opt/liltress-workstation"
SECRET_DIRECTORY="\${CONFIG_BASE_DIRECTORY}/secrets"

LYNIS_MIN_SCORE=${LYNIS_MIN_SCORE}

BANNER_MESSAGE="${BANNER_MESSAGE}"

SSH_BANNER_PATH="${SSH_BANNER_PATH}"
SSH_SERVICE_NAME="${SSH_SERVICE_NAME}"
SSH_MAX_AUTH_TRIES=${SSH_MAX_AUTH_TRIES}
SSH_CLIENT_ALIVE_INTERVAL=${SSH_CLIENT_ALIVE_INTERVAL}
SSH_CLIENT_ALIVE_COUNT_MAX=${SSH_CLIENT_ALIVE_COUNT_MAX}

WATCHDOG_CPU_LIMIT=${WATCHDOG_CPU_LIMIT}
WATCHDOG_LIMIT_NICE=${WATCHDOG_LIMIT_NICE}
WATCHDOG_LIMIT_IO_NICE=${WATCHDOG_LIMIT_IO_NICE}

MAIL_TEMPLATE="${MAIL_TEMPLATE}"
MAIL_ALERTS=${MAIL_ALERTS:-0}

PROJECT_SLUG="${PROJECT_SLUG}"

SSH_LOGIN_GRACE_TIME=${SSH_LOGIN_GRACE_TIME}

PAM_PASSWORD_MIN_LENGTH=${PAM_PASSWORD_MIN_LENGTH}
FAILLOCK_DENY=${FAILLOCK_DENY}
FAILLOCK_UNLOCK=${FAILLOCK_UNLOCK}
FAILLOCK_FAIL_INTERVAL=${FAILLOCK_FAIL_INTERVAL}

if [[ -n "\${INSTALL_DIRECTORY:-}" && -f "\${INSTALL_DIRECTORY}/config/user.conf" ]]; then
    # shellcheck disable=SC1091
    source "\${INSTALL_DIRECTORY}/config/user.conf"
fi
if [[ -n "\${INSTALL_DIRECTORY:-}" && -f "\${INSTALL_DIRECTORY}/config/secrets.conf" ]]; then
    # shellcheck disable=SC1091
    source "\${INSTALL_DIRECTORY}/config/secrets.conf"
fi
EOF
    chmod 644 "${dest}"
}

write_user_config() {
    local dest="$1"
    cat > "${dest}" << EOF
# =============================================================================
# File       : config/user.conf
# Updated at : 2026-11-07
# Creator    : palarchsys
# =============================================================================

LANGUAGE="${LANGUAGE:-en}"

EOF
    chmod 644 "${dest}"
}

write_secret_config() {
    local dest="$1"
    local old_umask
    old_umask="$(umask)"
    umask 077
    cat > "${dest}" << EOF
# =============================================================================
# File       : config/secrets.conf
# Updated at : 2026-10-05
# Creator    : palarchsys
# =============================================================================

SECRET_PREPARED=1
UBUNTU_PRO_TOKEN="${UBUNTU_PRO_TOKEN}"
POSTFIX_SMTP_LOGIN="${POSTFIX_SMTP_LOGIN}"
POSTFIX_MAIL_ADDRESS="${POSTFIX_MAIL_ADDRESS}"
POSTFIX_MAIL_PASSWORD="${POSTFIX_MAIL_PASSWORD}"
POSTFIX_MAIL_SMTP="${POSTFIX_MAIL_SMTP}"
WATCHDOG_MAIL="${WATCHDOG_MAIL}"

EOF
    chmod 600 "${dest}"
    umask "${old_umask}"
}

scan_config_dollar() {
    local file="$1" label="$2" stripped
    if grep -q '`' "${file}"; then
        log_config_error "$(get_text configure.backtick-forbidden "${label}")"
    fi
    if grep -q '\$(' "${file}"; then
        log_config_error "$(get_text configure.command-subst-forbidden "${label}")"
    fi
    stripped="$(sed -E \
        -e 's/\$\{INSTALL_DIRECTORY:-\}//g' \
        -e 's/\$\{INSTALL_DIRECTORY\}//g' \
        -e 's/\$\{PROJECT_SLUG\}//g' \
        -e 's/\$\{CONFIG_BASE_DIRECTORY\}//g' \
        "${file}")"
    if grep -q '\$' <<< "${stripped}"; then
        log_config_error "$(get_text configure.dollar-outside-r-f-rences-autoris-es-w-project-s "${label}")"
    fi
}

validate_values() {
    local label_g="global.conf" label_s="secrets.conf"

    [[ "${CONFIG_PREPARED:-}" == "1" ]] || log_config_error "$(get_text configure.config-prepared-must "${label_g}")"
    [[ "${PROJECT_NAME:-}" =~ ^[A-Za-z0-9][A-Za-z0-9\ ._-]{0,62}$ ]] || log_config_error "$(get_text configure.g-project-name-invalid-example-liltress-workstat "${label_g}" "${PROJECT_NAME:-}")"
    [[ "${PROJECT_SLUG:-}" == "liltress-workstation" ]] || log_config_error "$(get_text configure.w-project-slug-invalid-example-liltress-workstat "${label_g}" "${PROJECT_SLUG:-}")"
    [[ "${PROJECT_VERSION:-}" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || log_config_error "$(get_text configure.g-project-version-invalid-example-0-2 "${label_g}" "${PROJECT_VERSION:-}")"
    if [[ -n "${LANGUAGE:-}" ]] && ! check_language "${LANGUAGE}"; then
        log_config_error "$(get_text configure.g-language-invalid-values-in-fr-of-es "${label_g}" "${LANGUAGE}")"
    fi
    check_port "${LYNIS_MIN_SCORE:-x}" 0 100 || log_config_error "$(get_text configure.g-lynis-min-score-invalid-example-80 "${label_g}" "${LYNIS_MIN_SCORE:-}")"
    [[ -n "${BANNER_MESSAGE:-}" && "${BANNER_MESSAGE}" != *'$('* && "${BANNER_MESSAGE}" != *'`'* ]] || log_config_error "$(get_text configure.g-banner-message-empty-yet-no-safe "${label_g}")"
    check_absolute_path "${SSH_BANNER_PATH:-}" || log_config_error "$(get_text configure.g-ssh-banner-path-invalid-example-etc-ssh-sshd-b "${label_g}" "${SSH_BANNER_PATH:-}")"
    [[ "${SSH_SERVICE_NAME:-}" == "ssh" ]] || log_config_error "$(get_text configure.g-ssh-service-name-invalid-example-ssh "${label_g}" "${SSH_SERVICE_NAME:-}")"
    check_port "${SSH_MAX_AUTH_TRIES:-x}" 1 10 || log_config_error "$(get_text configure.g-ssh-max-auth-tries-invalid-example-4 "${label_g}" "${SSH_MAX_AUTH_TRIES:-}")"
    check_port "${SSH_CLIENT_ALIVE_INTERVAL:-x}" 30 3600 || log_config_error "$(get_text configure.g-ssh-client-alive-interval-invalid-example-300 "${label_g}" "${SSH_CLIENT_ALIVE_INTERVAL:-}")"
    check_port "${SSH_CLIENT_ALIVE_COUNT_MAX:-x}" 1 10 || log_config_error "$(get_text configure.g-ssh-client-alive-count-max-invalid-example-2 "${label_g}" "${SSH_CLIENT_ALIVE_COUNT_MAX:-}")"
    check_port "${SSH_LOGIN_GRACE_TIME:-x}" 10 120 || log_config_error "$(get_text configure.w-ssh-login-grace-time-invalid-example-30 "${label_g}" "${SSH_LOGIN_GRACE_TIME:-}")"
    check_port "${PAM_PASSWORD_MIN_LENGTH:-x}" 8 32 || log_config_error "$(get_text configure.w-pam-password-min-length-invalid-example-12 "${label_g}" "${PAM_PASSWORD_MIN_LENGTH:-}")"
    check_port "${FAILLOCK_DENY:-x}" 3 20 || log_config_error "$(get_text configure.w-faillock-deny-invalid-example-8 "${label_g}" "${FAILLOCK_DENY:-}")"
    check_port "${FAILLOCK_UNLOCK:-x}" 60 86400 || log_config_error "$(get_text configure.w-faillock-unlock-invalid-example-600 "${label_g}" "${FAILLOCK_UNLOCK:-}")"
    check_port "${FAILLOCK_FAIL_INTERVAL:-x}" 60 86400 || log_config_error "$(get_text configure.w-faillock-fail-interval-invalid-example-900 "${label_g}" "${FAILLOCK_FAIL_INTERVAL:-}")"
    check_port "${WATCHDOG_CPU_LIMIT:-x}" 1 100 || log_config_error "$(get_text configure.g-watchdog-cpu-limit-invalid-example-50 "${label_g}" "${WATCHDOG_CPU_LIMIT:-}")"
    check_port "${WATCHDOG_LIMIT_NICE:-x}" 0 19 || log_config_error "$(get_text configure.g-watchdog-limit-nice-invalid-example-19 "${label_g}" "${WATCHDOG_LIMIT_NICE:-}")"
    check_port "${WATCHDOG_LIMIT_IO_NICE:-x}" 0 7 || log_config_error "$(get_text configure.g-watchdog-limit-io-nice-invalid-example-3 "${label_g}" "${WATCHDOG_LIMIT_IO_NICE:-}")"
    [[ "${MAIL_ALERTS:-}" =~ ^[01]$ ]] || log_config_error "$(get_text configure.g-mail-alerts-invalid-example-0-or-1 "${label_g}" "${MAIL_ALERTS:-}")"
    [[ "${MAIL_TEMPLATE:-mail.html}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.html$ ]] || log_config_error "$(get_text configure.g-mail-template-invalid-example-mail-html "${label_g}" "${MAIL_TEMPLATE:-}")"
    if [[ -n "${CONFIG_ROOT:-}" && -d "${CONFIG_ROOT}/template" && ! -f "${CONFIG_ROOT}/template/${MAIL_TEMPLATE:-mail.html}" ]]; then
        log_config_error "$(get_text configure.g-mail-template-not-found-example-a-file-html-of "${label_g}" "${MAIL_TEMPLATE:-mail.html}")"
    fi
    [[ "${CONFIG_BASE_DIRECTORY:-}" == "/opt/liltress-workstation" ]] || log_config_error "$(get_text configure.g-config-base-directory-invalid-example-opt-lilt "${label_g}" "${CONFIG_BASE_DIRECTORY:-}")"
    [[ "${SECRET_DIRECTORY:-}" == "/opt/liltress-workstation/secrets" ]] || log_config_error "$(get_text configure.g-secret-directory-invalid-example-opt-liltress "${label_g}" "${SECRET_DIRECTORY:-}")"

    [[ "${SECRET_PREPARED:-}" == "1" ]] || log_config_error "$(get_text configure.secret-prepared-must "${label_s}")"
    check_pro_token "${UBUNTU_PRO_TOKEN:-}" || log_config_error "$(get_text configure.g-ubuntu-pro-token-invalid-example-the-token-alp "${label_s}")"
    if [[ "${MAIL_ALERTS}" == "1" ]]; then
        check_email "${POSTFIX_SMTP_LOGIN:-}" || log_config_error "$(get_text configure.g-postfix-smtp-login-must-be-an-address-email-ex "${label_s}" "${POSTFIX_SMTP_LOGIN:-}")"
        check_email "${POSTFIX_MAIL_ADDRESS:-}" || log_config_error "$(get_text configure.g-postfix-mail-address-must-be-an-address-email "${label_s}" "${POSTFIX_MAIL_ADDRESS:-}")"
        check_app_password "${POSTFIX_MAIL_PASSWORD:-}" || log_config_error "$(get_text configure.g-postfix-mail-password-invalid-example-the-pass "${label_s}")"
        check_smtp "${POSTFIX_MAIL_SMTP:-}" || log_config_error "$(get_text configure.g-postfix-mail-smtp-invalid-example-smtp-mail-ou "${label_s}" "${POSTFIX_MAIL_SMTP:-}")"
        check_email "${WATCHDOG_MAIL:-}" || log_config_error "$(get_text configure.g-watchdog-mail-must-be-an-address-email-example "${label_s}" "${WATCHDOG_MAIL:-}")"
        [[ "${WATCHDOG_MAIL:-}" == "${POSTFIX_MAIL_ADDRESS:-}" ]] || log_config_error "$(get_text configure.g-watchdog-mail-must-be-the-same-address-that-g "${label_s}")"
    else
        [[ -z "${POSTFIX_SMTP_LOGIN:-}${POSTFIX_MAIL_ADDRESS:-}${POSTFIX_MAIL_PASSWORD:-}${POSTFIX_MAIL_SMTP:-}${WATCHDOG_MAIL:-}" ]] \
            || log_config_error "$(get_text configure.the-fields-e-mail-must-be-vides-when-the-alerts "${label_s}")"
    fi
}

require_prepared_config() {
    local root="$1"
    local g="${root}/config/global.conf"
    local u="${root}/config/user.conf"
    local s="${root}/config/secrets.conf"
    local mode src_count

    reset_config

    if [[ ! -f "${g}" ]]; then
        log_config_error "$(get_text configure.global-conf-absent-example-liltress-configures "${g}")"
    fi
    if [[ ! -f "${u}" ]]; then
        log_config_error "$(get_text configure.user-conf-absent "${u}")"
    fi
    if [[ ! -f "${s}" ]]; then
        log_config_error "$(get_text configure.secrets-conf-absent-example-liltress-configures "${s}")"
    fi
    if [[ ! -f "${g}" || ! -f "${u}" || ! -f "${s}" ]]; then
        emit_config
        return 1
    fi

    if ! bash -n "${g}" 2>/dev/null; then
        log_config_error "$(get_text configure.global-conf-syntax-shell-invalid-example-liltres)"
    fi
    if ! bash -n "${s}" 2>/dev/null; then
        log_config_error "$(get_text configure.secrets-conf-syntax-shell-invalid-example-liltre)"
    fi
    scan_config_dollar "${g}" "global.conf"
    scan_config_dollar "${u}" "user.conf"
    scan_config_dollar "${s}" "secrets.conf"

    src_count="$(grep -cE '(^|[[:space:]])(source|\.)[[:space:]]' "${g}" || true)"
    if [[ "${src_count}" != "2" ]] \
        || ! grep -q 'source "${INSTALL_DIRECTORY}/config/user.conf"' "${g}" \
        || ! grep -q 'source "${INSTALL_DIRECTORY}/config/secrets.conf"' "${g}"; then
        log_config_error "$(get_text configure.global-conf-the-only-command-source-allowed-load)"
    fi
    if grep -qE '(^|[[:space:]])(source|\.)[[:space:]]' "${u}"; then
        log_config_error "$(get_text configure.user-conf-no-source)"
    fi
    if grep -qE '(^|[[:space:]])(source|\.)[[:space:]]' "${s}"; then
        log_config_error "$(get_text configure.secrets-conf-no-command-source-example-only-of-t)"
    fi

    mode="$(stat -c '%a' "${s}" 2>/dev/null || echo '')"
    if [[ "${mode}" != "600" && "${mode}" != "400" ]]; then
        log_config_error "$(get_text configure.secrets-conf-mode "${mode:-inconnues}")"
    fi

    if [[ ${#CONFIG_ERRORS[@]} -gt 0 ]]; then
        emit_config
        return 1
    fi

    set +u
    # shellcheck disable=SC1090
    source "${g}"
    # shellcheck disable=SC1090
    source "${u}"
    # shellcheck disable=SC1090
    source "${s}"
    set -u

    CONFIG_ROOT="${root}"
    validate_values
    emit_config
}
