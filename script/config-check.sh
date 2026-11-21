#!/usr/bin/env bash
# =============================================================================
# File       : script/config-check.sh
# Updated at : 2026-11-16
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Confirm the prepared configuration files.
# Note       : A dollar outside the allowed references stops the file.
# -----------------------------------------------------------------------------


PRODUCT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${PRODUCT_ROOT}/../share/core/boot/bootstrap.sh" ]]; then
    # shellcheck disable=SC1091
    source "${PRODUCT_ROOT}/../share/core/boot/bootstrap.sh"
elif [[ -f "${PRODUCT_ROOT}/core/boot/bootstrap.sh" ]]; then
    # shellcheck disable=SC1091
    source "${PRODUCT_ROOT}/core/boot/bootstrap.sh"
else
    printf 'bootstrap core not found from %s\n' "${PRODUCT_ROOT}" >&2
    exit 1
fi
source_core config/config-validators.sh
source_core log/log.sh

# Running this file alone is refused.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '%s\n' "$(get_text configure.use-liltress-configures-check-n)" >&2
    exit 1
fi

# Refused values stay here until the caller prints them.
CONFIG_ERRORS=()

# A token is 6 to 100 letters or digits.
check_pro_token() {
    [[ "$1" =~ ^[A-Za-z0-9]{6,100}$ ]]
}

# An empty banner receives the standard notice.
set_config_banner() {
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

# Saved values fill any name that is still empty.
set_config_default() {
    : "${PROJECT_NAME:=Liltress Workstation}"
    : "${PROJECT_SLUG:=liltress-workstation}"
    : "${PROJECT_VERSION:=0.2}"
    : "${LYNIS_MIN_SCORE:=80}"
    : "${SSH_BANNER_PATH:=/etc/ssh/sshd_banner}"
    : "${SSH_SERVICE_NAME:=ssh}"
    : "${SSH_MAX_AUTH_TRIES:=3}"
    : "${SSH_CLIENT_ALIVE_INTERVAL:=300}"
    : "${SSH_CLIENT_ALIVE_COUNT_MAX:=0}"
    : "${SSH_LOGIN_GRACE_TIME:=20}"
    : "${SSH_TCP_KEEPALIVE:=no}"
    : "${SSH_MAX_SESSIONS:=2}"
    : "${PAM_PASSWORD_MIN_LENGTH:=12}"
    : "${FAILLOCK_DENY:=5}"
    : "${FAILLOCK_UNLOCK:=900}"
    : "${FAILLOCK_FAIL_INTERVAL:=900}"
    : "${SSH_USER:=drawbridge}"
    : "${SSH_GROUP:=drawbridge}"
    : "${SSH_PORT:=2501}"
    : "${TAILSCALE_AUTH_KEY:=}"
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
    set_config_banner
}

# Identity, paths, and the notice come first.
write_global_opening() {
    local dest="$1"
    cat >"${dest}" <<EOF
# =============================================================================
# File       : config/global.conf
# Updated at : 2026-11-11
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
SSH_TCP_KEEPALIVE=${SSH_TCP_KEEPALIVE}
SSH_MAX_SESSIONS=${SSH_MAX_SESSIONS}

WATCHDOG_CPU_LIMIT=${WATCHDOG_CPU_LIMIT}
WATCHDOG_LIMIT_NICE=${WATCHDOG_LIMIT_NICE}
WATCHDOG_LIMIT_IO_NICE=${WATCHDOG_LIMIT_IO_NICE}

MAIL_TEMPLATE="${MAIL_TEMPLATE}"
MAIL_ALERTS=${MAIL_ALERTS:-0}
EOF
}

# Account policy and the two inclusions follow.
write_global_closing() {
    local dest="$1"
    cat >>"${dest}" <<EOF

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
if [[ -n "\${INSTALL_DIRECTORY:-}" && -r "\${INSTALL_DIRECTORY}/config/secrets.conf" ]]; then
    # shellcheck disable=SC1091
    source "\${INSTALL_DIRECTORY}/config/secrets.conf"
fi
EOF
}

# The shared file is assembled, then its mode becomes 644.
write_global_config() {
    local dest="$1"
    write_global_opening "${dest}"
    write_global_closing "${dest}"
    chmod 644 "${dest}"
}

# The language file stays readable by every account.
write_user_config() {
    local dest="$1"
    cat >"${dest}" <<EOF
# =============================================================================
# File       : config/user.conf
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

LANGUAGE="${LANGUAGE:-en}"
SSH_USER="${SSH_USER:-drawbridge}"
SSH_GROUP="${SSH_GROUP:-drawbridge}"
SSH_PORT=${SSH_PORT:-2501}

EOF
    chmod 644 "${dest}"
}

# The secret file is readable only by its owner.
write_secret_config() {
    local dest="$1"
    local old_umask
    old_umask="$(umask)"
    umask 077
    cat >"${dest}" <<EOF
# =============================================================================
# File       : config/secrets.conf
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

SECRET_PREPARED=1
UBUNTU_PRO_TOKEN="${UBUNTU_PRO_TOKEN}"
TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY}"
POSTFIX_SMTP_LOGIN="${POSTFIX_SMTP_LOGIN}"
POSTFIX_MAIL_ADDRESS="${POSTFIX_MAIL_ADDRESS}"
POSTFIX_MAIL_PASSWORD="${POSTFIX_MAIL_PASSWORD}"
POSTFIX_MAIL_SMTP="${POSTFIX_MAIL_SMTP}"
WATCHDOG_MAIL="${WATCHDOG_MAIL}"

EOF
    chmod 600 "${dest}"
    umask "${old_umask}"
}

# A backtick, a command substitution, or a stray dollar is refused.
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
    if grep -q '\$' <<<"${stripped}"; then
        log_config_error "$(get_text configure.dollar-outside-r-f-rences-autoris-es-w-project-s "${label}")"
    fi
}

# The title, the slug, the version, and the language are confirmed.
check_prepared_project() {
    local label_g="$1"
    [[ "${CONFIG_PREPARED:-}" == "1" ]] || log_config_error "$(get_text configure.config-prepared-must "${label_g}")"
    [[ "${PROJECT_NAME:-}" =~ ^[A-Za-z0-9][A-Za-z0-9\ ._-]{0,62}$ ]] || log_config_error "$(get_text configure.g-project-name-invalid-example-liltress-workstat "${label_g}" "${PROJECT_NAME:-}")"
    [[ "${PROJECT_SLUG:-}" == "liltress-workstation" ]] || log_config_error "$(get_text configure.w-project-slug-invalid-example-liltress-workstat "${label_g}" "${PROJECT_SLUG:-}")"
    [[ "${PROJECT_VERSION:-}" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || log_config_error "$(get_text configure.g-project-version-invalid-example-0-2 "${label_g}" "${PROJECT_VERSION:-}")"
    if [[ -n "${LANGUAGE:-}" ]] && ! check_language "${LANGUAGE}"; then
        log_config_error "$(get_text configure.g-language-invalid-values-in-fr-of-es "${label_g}" "${LANGUAGE}")"
    fi
}

# The score, the notice, and the service name are confirmed.
check_prepared_notice() {
    local label_g="$1"
    check_port "${LYNIS_MIN_SCORE:-x}" 0 100 || log_config_error "$(get_text configure.g-lynis-min-score-invalid-example-80 "${label_g}" "${LYNIS_MIN_SCORE:-}")"
    [[ -n "${BANNER_MESSAGE:-}" && "${BANNER_MESSAGE}" != *'$('* && "${BANNER_MESSAGE}" != *'`'* ]] || log_config_error "$(get_text configure.g-banner-message-empty-yet-no-safe "${label_g}")"
    check_absolute_path "${SSH_BANNER_PATH:-}" || log_config_error "$(get_text configure.g-ssh-banner-path-invalid-example-etc-ssh-sshd-b "${label_g}" "${SSH_BANNER_PATH:-}")"
    [[ "${SSH_SERVICE_NAME:-}" == "ssh" ]] || log_config_error "$(get_text configure.g-ssh-service-name-invalid-example-ssh "${label_g}" "${SSH_SERVICE_NAME:-}")"
}

# Remote entry timings stay inside their ranges.
check_prepared_ssh() {
    local label_g="$1"
    check_port "${SSH_MAX_AUTH_TRIES:-x}" 1 10 || log_config_error "$(get_text configure.g-ssh-max-auth-tries-invalid-example-4 "${label_g}" "${SSH_MAX_AUTH_TRIES:-}")"
    check_port "${SSH_CLIENT_ALIVE_INTERVAL:-x}" 30 3600 || log_config_error "$(get_text configure.g-ssh-client-alive-interval-invalid-example-300 "${label_g}" "${SSH_CLIENT_ALIVE_INTERVAL:-}")"
    check_port "${SSH_CLIENT_ALIVE_COUNT_MAX:-x}" 0 10 || log_config_error "$(get_text configure.g-ssh-client-alive-count-max-invalid-example-2 "${label_g}" "${SSH_CLIENT_ALIVE_COUNT_MAX:-}")"
    check_port "${SSH_LOGIN_GRACE_TIME:-x}" 10 120 || log_config_error "$(get_text configure.w-ssh-login-grace-time-invalid-example-30 "${label_g}" "${SSH_LOGIN_GRACE_TIME:-}")"
    check_port "${SSH_MAX_SESSIONS:-x}" 1 10 || log_config_error "$(get_text configure.g-ssh-max-auth-tries-invalid-example-4 "${label_g}" "${SSH_MAX_SESSIONS:-}")"
    [[ "${SSH_TCP_KEEPALIVE:-}" == "yes" || "${SSH_TCP_KEEPALIVE:-}" == "no" ]] || log_config_error "$(get_text configure.g-ssh-service-name-invalid-example-ssh "${label_g}" "${SSH_TCP_KEEPALIVE:-}")"
}

# The password length and the lockout timings stay inside their ranges.
check_prepared_lock() {
    local label_g="$1"
    check_port "${PAM_PASSWORD_MIN_LENGTH:-x}" 8 32 || log_config_error "$(get_text configure.w-pam-password-min-length-invalid-example-12 "${label_g}" "${PAM_PASSWORD_MIN_LENGTH:-}")"
    check_port "${FAILLOCK_DENY:-x}" 3 20 || log_config_error "$(get_text configure.w-faillock-deny-invalid-example-8 "${label_g}" "${FAILLOCK_DENY:-}")"
    check_port "${FAILLOCK_UNLOCK:-x}" 60 86400 || log_config_error "$(get_text configure.w-faillock-unlock-invalid-example-600 "${label_g}" "${FAILLOCK_UNLOCK:-}")"
    check_port "${FAILLOCK_FAIL_INTERVAL:-x}" 60 86400 || log_config_error "$(get_text configure.w-faillock-fail-interval-invalid-example-900 "${label_g}" "${FAILLOCK_FAIL_INTERVAL:-}")"
}

# The three resource limits stay inside their ranges.
check_prepared_watch() {
    local label_g="$1"
    check_port "${WATCHDOG_CPU_LIMIT:-x}" 1 100 || log_config_error "$(get_text configure.g-watchdog-cpu-limit-invalid-example-50 "${label_g}" "${WATCHDOG_CPU_LIMIT:-}")"
    check_port "${WATCHDOG_LIMIT_NICE:-x}" 0 19 || log_config_error "$(get_text configure.g-watchdog-limit-nice-invalid-example-19 "${label_g}" "${WATCHDOG_LIMIT_NICE:-}")"
    check_port "${WATCHDOG_LIMIT_IO_NICE:-x}" 0 7 || log_config_error "$(get_text configure.g-watchdog-limit-io-nice-invalid-example-3 "${label_g}" "${WATCHDOG_LIMIT_IO_NICE:-}")"
}

# Message files and the two directories are confirmed.
check_prepared_layout() {
    local label_g="$1"
    [[ "${MAIL_ALERTS:-}" =~ ^[01]$ ]] || log_config_error "$(get_text configure.g-mail-alerts-invalid-example-0-or-1 "${label_g}" "${MAIL_ALERTS:-}")"
    [[ "${MAIL_TEMPLATE:-mail.html}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.html$ ]] || log_config_error "$(get_text configure.g-mail-template-invalid-example-mail-html "${label_g}" "${MAIL_TEMPLATE:-}")"
    if [[ -n "${CONFIG_ROOT:-}" && -d "${CONFIG_ROOT}/template" && ! -f "${CONFIG_ROOT}/template/${MAIL_TEMPLATE:-mail.html}" ]]; then
        log_config_error "$(get_text configure.g-mail-template-not-found-example-a-file-html-of "${label_g}" "${MAIL_TEMPLATE:-mail.html}")"
    fi
    [[ "${CONFIG_BASE_DIRECTORY:-}" == "/opt/liltress-workstation" ]] || log_config_error "$(get_text configure.g-config-base-directory-invalid-example-opt-lilt "${label_g}" "${CONFIG_BASE_DIRECTORY:-}")"
    [[ "${SECRET_DIRECTORY:-}" == "/opt/liltress-workstation/secrets" ]] || log_config_error "$(get_text configure.g-secret-directory-invalid-example-opt-liltress "${label_g}" "${SECRET_DIRECTORY:-}")"
}

# The secret flag and the token shape are confirmed.
check_prepared_token() {
    local label_s="$1"
    [[ "${SECRET_PREPARED:-}" == "1" ]] || log_config_error "$(get_text configure.secret-prepared-must "${label_s}")"
    check_pro_token "${UBUNTU_PRO_TOKEN:-}" || log_config_error "$(get_text configure.g-ubuntu-pro-token-invalid-example-the-token-alp "${label_s}")"
}

# Alert addresses are real, and the two addresses are the same.
check_prepared_mail_on() {
    local label_s="$1"
    check_email "${POSTFIX_SMTP_LOGIN:-}" || log_config_error "$(get_text configure.g-postfix-smtp-login-must-be-an-address-email-ex "${label_s}" "${POSTFIX_SMTP_LOGIN:-}")"
    check_email "${POSTFIX_MAIL_ADDRESS:-}" || log_config_error "$(get_text configure.g-postfix-mail-address-must-be-an-address-email "${label_s}" "${POSTFIX_MAIL_ADDRESS:-}")"
    check_app_password "${POSTFIX_MAIL_PASSWORD:-}" || log_config_error "$(get_text configure.g-postfix-mail-password-invalid-example-the-pass "${label_s}")"
    check_smtp "${POSTFIX_MAIL_SMTP:-}" || log_config_error "$(get_text configure.g-postfix-mail-smtp-invalid-example-smtp-mail-ou "${label_s}" "${POSTFIX_MAIL_SMTP:-}")"
    check_email "${WATCHDOG_MAIL:-}" || log_config_error "$(get_text configure.g-watchdog-mail-must-be-an-address-email-example "${label_s}" "${WATCHDOG_MAIL:-}")"
    [[ "${WATCHDOG_MAIL:-}" == "${POSTFIX_MAIL_ADDRESS:-}" ]] || log_config_error "$(get_text configure.g-watchdog-mail-must-be-the-same-address-that-g "${label_s}")"
}

# Alert fields stay empty when alerts are off.
check_prepared_mail_off() {
    local label_s="$1"
    [[ -z "${POSTFIX_SMTP_LOGIN:-}${POSTFIX_MAIL_ADDRESS:-}${POSTFIX_MAIL_PASSWORD:-}${POSTFIX_MAIL_SMTP:-}${WATCHDOG_MAIL:-}" ]] \
        || log_config_error "$(get_text configure.the-fields-e-mail-must-be-vides-when-the-alerts "${label_s}")"
}

# Alert mail is either filled in or left empty.
check_prepared_mail() {
    local label_s="$1"
    if [[ "${MAIL_ALERTS}" == "1" ]]; then
        check_prepared_mail_on "${label_s}"
    else
        check_prepared_mail_off "${label_s}"
    fi
}

# Every prepared value is confirmed in the same order.
validate_values() {
    local label_g="global.conf" label_s="secrets.conf"
    check_prepared_project "${label_g}"
    check_prepared_notice "${label_g}"
    check_prepared_ssh "${label_g}"
    check_prepared_lock "${label_g}"
    check_prepared_watch "${label_g}"
    check_prepared_layout "${label_g}"
    check_prepared_token "${label_s}"
    check_prepared_mail "${label_s}"
}

# Missing files stop the command.
require_config_files() {
    local global_file="$1" user_file="$2" secret_file="$3"
    if [[ ! -f "${global_file}" ]]; then
        log_config_error "$(get_text configure.global-conf-absent-example-liltress-configures "${global_file}")"
    fi
    if [[ ! -f "${user_file}" ]]; then
        log_config_error "$(get_text configure.user-conf-absent "${user_file}")"
    fi
    if [[ ! -f "${secret_file}" ]]; then
        log_config_error "$(get_text configure.secrets-conf-absent-example-liltress-configures "${secret_file}")"
    fi
    if [[ ! -f "${global_file}" || ! -f "${user_file}" || ! -f "${secret_file}" ]]; then
        emit_config
        return 1
    fi
}

# The shell syntax of the two main files is confirmed.
check_config_syntax() {
    local global_file="$1" secret_file="$2"
    if ! bash -n "${global_file}" 2>/dev/null; then
        log_config_error "$(get_text configure.global-conf-syntax-shell-invalid-example-liltres)"
    fi
    if ! bash -n "${secret_file}" 2>/dev/null; then
        log_config_error "$(get_text configure.secrets-conf-syntax-shell-invalid-example-liltre)"
    fi
}

# Only the two allowed inclusions stay in the shared file.
check_config_sources() {
    local global_file="$1" user_file="$2" secret_file="$3" src_count
    src_count="$(grep -cE '(^|[[:space:]])(source|\.)[[:space:]]' "${global_file}" || true)"
    if [[ "${src_count}" != "2" ]] \
        || ! grep -q 'source "${INSTALL_DIRECTORY}/config/user.conf"' "${global_file}" \
        || ! grep -q 'source "${INSTALL_DIRECTORY}/config/secrets.conf"' "${global_file}"; then
        log_config_error "$(get_text configure.global-conf-the-only-command-source-allowed-load)"
    fi
    if grep -qE '(^|[[:space:]])(source|\.)[[:space:]]' "${user_file}"; then
        log_config_error "$(get_text configure.user-conf-no-source)"
    fi
    if grep -qE '(^|[[:space:]])(source|\.)[[:space:]]' "${secret_file}"; then
        log_config_error "$(get_text configure.secrets-conf-no-command-source-example-only-of-t)"
    fi
}

# The secret file mode is 600 or 400.
check_config_mode() {
    local secret_file="$1" mode
    mode="$(stat -c '%a' "${secret_file}" 2>/dev/null || echo '')"
    if [[ "${mode}" != "600" && "${mode}" != "400" ]]; then
        log_config_error "$(get_text configure.secrets-conf-mode "${mode:-inconnues}")"
    fi
}

# The three files are opened, then the root is recorded.
load_config_files() {
    local root="$1" global_file="$2" user_file="$3" secret_file="$4"
    set +u
    # shellcheck disable=SC1090
    source "${global_file}"
    # shellcheck disable=SC1090
    source "${user_file}"
    # shellcheck disable=SC1090
    source "${secret_file}"
    set -u
    CONFIG_ROOT="${root}"
}

# The three files are accepted only when every value is safe.
require_prepared_config() {
    local root="$1"
    local global_file="${root}/config/global.conf"
    local user_file="${root}/config/user.conf"
    local secret_file="${root}/config/secrets.conf"
    reset_config
    require_config_files "${global_file}" "${user_file}" "${secret_file}" || return 1
    check_config_syntax "${global_file}" "${secret_file}"
    scan_config_dollar "${global_file}" "global.conf"
    scan_config_dollar "${user_file}" "user.conf"
    scan_config_dollar "${secret_file}" "secrets.conf"
    check_config_sources "${global_file}" "${user_file}" "${secret_file}"
    check_config_mode "${secret_file}"
    if [[ ${#CONFIG_ERRORS[@]} -gt 0 ]]; then
        emit_config
        return 1
    fi
    load_config_files "${root}" "${global_file}" "${user_file}" "${secret_file}"
    validate_values
    emit_config
}
