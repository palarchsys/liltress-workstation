#!/usr/bin/env bash
# =============================================================================
# File       : script/config-check.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

G_PRODUCT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${G_PRODUCT_ROOT}/../core/bootstrap.sh" ]]; then
    # shellcheck disable=SC1091
    source "${G_PRODUCT_ROOT}/../core/bootstrap.sh"
elif [[ -f "${G_PRODUCT_ROOT}/core/bootstrap.sh" ]]; then
    # shellcheck disable=SC1091
    source "${G_PRODUCT_ROOT}/core/bootstrap.sh"
else
    printf 'bootstrap core not found from %s\n' "${G_PRODUCT_ROOT}" >&2
    exit 1
fi
source_core config-validators.sh
source_core log.sh

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '%s\n' "$(get_text configure.use-liltress-configures-check-n)" >&2
    exit 1
fi

W_CONFIG_ERRORS=()

reset_config() {
    W_CONFIG_ERRORS=()
}

log_config_error() {
    W_CONFIG_ERRORS+=("$1")
}

emit_config() {
    local e
    if [[ ${#W_CONFIG_ERRORS[@]} -eq 0 ]]; then
        return 0
    fi
    for e in "${W_CONFIG_ERRORS[@]}"; do
        printf "$(get_text configure.error "${e}")" >&2
    done
    return 1
}

check_pro_token() {
    [[ "$1" =~ ^[A-Za-z0-9]{6,100}$ ]]
}

set_config_default() {
    : "${G_PROJECT_NAME:=Liltress Workstation}"
    : "${W_PROJECT_SLUG:=liltress-workstation}"
    : "${G_PROJECT_VERSION:=0.2}"
    : "${G_DEBUG_INSTALL_LOG:=0}"
    : "${G_MODE_TEST:=1}"
    : "${G_LYNIS_MIN_SCORE:=80}"
    : "${W_OS_ID:=ubuntu}"
    : "${W_OS_VERSION:=26.04}"
    : "${G_SSH_BANNER_PATH:=/etc/ssh/sshd_banner}"
    : "${G_SSH_SERVICE_NAME:=ssh}"
    : "${G_SSH_MAX_AUTH_TRIES:=4}"
    : "${G_SSH_CLIENT_ALIVE_INTERVAL:=300}"
    : "${G_SSH_CLIENT_ALIVE_COUNT_MAX:=2}"
    : "${W_SSH_LOGIN_GRACE_TIME:=30}"
    : "${W_PAM_PASSWORD_MIN_LENGTH:=12}"
    : "${W_FAILLOCK_DENY:=8}"
    : "${W_FAILLOCK_UNLOCK:=600}"
    : "${W_FAILLOCK_FAIL_INTERVAL:=900}"
    : "${G_WATCHDOG_CPU_LIMIT:=50}"
    : "${G_WATCHDOG_LIMIT_NICE:=19}"
    : "${G_WATCHDOG_LIMIT_IO_NICE:=3}"
    : "${G_UBUNTU_PRO_TOKEN:=}"
    : "${G_MAIL_ALERTS:=0}"
    : "${G_RCLONE_ALERTS:=0}"
    : "${G_RCLONE_REMOTE:=gdrive}"
    : "${G_RCLONE_PATH:=liltress-alerts}"
    : "${G_MAIL_TEMPLATE:=mail.html}"
    : "${G_POSTFIX_SMTP_LOGIN:=}"
    : "${G_POSTFIX_MAIL_ADDRESS:=}"
    : "${G_POSTFIX_MAIL_PASSWORD:=}"
    : "${G_POSTFIX_MAIL_SMTP:=}"
    : "${G_WATCHDOG_MAIL:=}"
    if [[ -z "${G_BANNER_MESSAGE:-}" ]]; then
        G_BANNER_MESSAGE="***********************************************************************
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
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

# Shared

G_CONFIG_PREPARED=1
G_LANGUAGE="${G_LANGUAGE:-en}"

G_PROJECT_NAME="${G_PROJECT_NAME}"
G_PROJECT_VERSION="${G_PROJECT_VERSION}"

G_CONFIG_BASE_DIRECTORY="/opt/liltress-workstation"
G_SECRET_DIRECTORY="\${G_CONFIG_BASE_DIRECTORY}/secrets"

G_DEBUG_INSTALL_LOG=${G_DEBUG_INSTALL_LOG}

G_MODE_TEST=${G_MODE_TEST}

G_LYNIS_MIN_SCORE=${G_LYNIS_MIN_SCORE}

G_BANNER_MESSAGE="${G_BANNER_MESSAGE}"

G_SSH_BANNER_PATH="${G_SSH_BANNER_PATH}"
G_SSH_SERVICE_NAME="${G_SSH_SERVICE_NAME}"
G_SSH_MAX_AUTH_TRIES=${G_SSH_MAX_AUTH_TRIES}
G_SSH_CLIENT_ALIVE_INTERVAL=${G_SSH_CLIENT_ALIVE_INTERVAL}
G_SSH_CLIENT_ALIVE_COUNT_MAX=${G_SSH_CLIENT_ALIVE_COUNT_MAX}

G_WATCHDOG_CPU_LIMIT=${G_WATCHDOG_CPU_LIMIT}
G_WATCHDOG_LIMIT_NICE=${G_WATCHDOG_LIMIT_NICE}
G_WATCHDOG_LIMIT_IO_NICE=${G_WATCHDOG_LIMIT_IO_NICE}

G_MAIL_ALERTS=${G_MAIL_ALERTS}

G_RCLONE_ALERTS=${G_RCLONE_ALERTS}
G_RCLONE_REMOTE="${G_RCLONE_REMOTE}"
G_RCLONE_PATH="${G_RCLONE_PATH}"

G_MAIL_TEMPLATE="${G_MAIL_TEMPLATE}"

# Server

# Workstation

W_PROJECT_SLUG="${W_PROJECT_SLUG}"

W_OS_ID="${W_OS_ID}"
W_OS_VERSION="${W_OS_VERSION}"

W_SSH_LOGIN_GRACE_TIME=${W_SSH_LOGIN_GRACE_TIME}

W_PAM_PASSWORD_MIN_LENGTH=${W_PAM_PASSWORD_MIN_LENGTH}
W_FAILLOCK_DENY=${W_FAILLOCK_DENY}
W_FAILLOCK_UNLOCK=${W_FAILLOCK_UNLOCK}
W_FAILLOCK_FAIL_INTERVAL=${W_FAILLOCK_FAIL_INTERVAL}

if [[ -n "\${G_INSTALL_DIRECTORY:-}" && -f "\${G_INSTALL_DIRECTORY}/config/secrets.conf" ]]; then
    # shellcheck disable=SC1091
    source "\${G_INSTALL_DIRECTORY}/config/secrets.conf"
fi
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

# Shared

G_SECRET_PREPARED=1
G_UBUNTU_PRO_TOKEN="${G_UBUNTU_PRO_TOKEN}"
G_POSTFIX_SMTP_LOGIN="${G_POSTFIX_SMTP_LOGIN}"
G_POSTFIX_MAIL_ADDRESS="${G_POSTFIX_MAIL_ADDRESS}"
G_POSTFIX_MAIL_PASSWORD="${G_POSTFIX_MAIL_PASSWORD}"
G_POSTFIX_MAIL_SMTP="${G_POSTFIX_MAIL_SMTP}"
G_WATCHDOG_MAIL="${G_WATCHDOG_MAIL}"

# Server

# Workstation
EOF
    chmod 600 "${dest}"
    umask "${old_umask}"
}

scan_config_dollar() {
    local file="$1" label="$2" stripped
    if grep -q '`' "${file}"; then
        log_config_error "${label} : apostrophe inverse interdite."
    fi
    if grep -q '\$(' "${file}"; then
        log_config_error "${label} : \$(...) interdit."
    fi
    stripped="$(sed -E \
        -e 's/\$\{G_INSTALL_DIRECTORY:-\}//g' \
        -e 's/\$\{G_INSTALL_DIRECTORY\}//g' \
        -e 's/\$\{W_PROJECT_SLUG\}//g' \
        -e 's/\$\{G_CONFIG_BASE_DIRECTORY\}//g' \
        "${file}")"
    if grep -q '\$' <<< "${stripped}"; then
        log_config_error "$(get_text configure.dollar-outside-r-f-rences-autoris-es-w-project-s "${label}")"
    fi
}

validate_values() {
    local label_g="global.conf" label_s="secrets.conf"

    [[ "${G_CONFIG_PREPARED:-}" == "1" ]] || log_config_error "${label_g} : G_CONFIG_PREPARED doit valoir 1. exemple : ./liltress configure"
    [[ "${G_PROJECT_NAME:-}" =~ ^[A-Za-z0-9][A-Za-z0-9\ ._-]{0,62}$ ]] || log_config_error "$(get_text configure.g-project-name-invalid-example-liltress-workstat "${label_g}" "${G_PROJECT_NAME:-}")"
    [[ "${W_PROJECT_SLUG:-}" == "liltress-workstation" ]] || log_config_error "$(get_text configure.w-project-slug-invalid-example-liltress-workstat "${label_g}" "${W_PROJECT_SLUG:-}")"
    [[ "${G_PROJECT_VERSION:-}" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || log_config_error "$(get_text configure.g-project-version-invalid-example-0-2 "${label_g}" "${G_PROJECT_VERSION:-}")"
    [[ "${G_DEBUG_INSTALL_LOG:-}" =~ ^[01]$ ]] || log_config_error "$(get_text configure.g-debug-install-log-invalid-example-0 "${label_g}" "${G_DEBUG_INSTALL_LOG:-}")"
    [[ "${G_MODE_TEST:-}" =~ ^[01]$ ]] || log_config_error "$(get_text configure.g-mode-test-invalid-example-1 "${label_g}" "${G_MODE_TEST:-}")"
    if [[ -n "${G_LANGUAGE:-}" ]] && ! check_language "${G_LANGUAGE}"; then
        log_config_error "$(get_text configure.g-language-invalid-values-in-fr-of-es "${label_g}" "${G_LANGUAGE}")"
    fi
    check_port "${G_LYNIS_MIN_SCORE:-x}" 0 100 || log_config_error "$(get_text configure.g-lynis-min-score-invalid-example-80 "${label_g}" "${G_LYNIS_MIN_SCORE:-}")"
    [[ "${W_OS_ID:-}" == "ubuntu" ]] || log_config_error "$(get_text configure.w-os-id-invalid-example-ubuntu "${label_g}" "${W_OS_ID:-}")"
    [[ "${W_OS_VERSION:-}" == "26.04" ]] || log_config_error "$(get_text configure.w-os-version-invalid-example-26-04 "${label_g}" "${W_OS_VERSION:-}")"
    [[ -n "${G_BANNER_MESSAGE:-}" && "${G_BANNER_MESSAGE}" != *'$('* && "${G_BANNER_MESSAGE}" != *'`'* ]] || log_config_error "$(get_text configure.g-banner-message-empty-yet-no-safe "${label_g}")"
    check_absolute_path "${G_SSH_BANNER_PATH:-}" || log_config_error "$(get_text configure.g-ssh-banner-path-invalid-example-etc-ssh-sshd-b "${label_g}" "${G_SSH_BANNER_PATH:-}")"
    [[ "${G_SSH_SERVICE_NAME:-}" == "ssh" ]] || log_config_error "$(get_text configure.g-ssh-service-name-invalid-example-ssh "${label_g}" "${G_SSH_SERVICE_NAME:-}")"
    check_port "${G_SSH_MAX_AUTH_TRIES:-x}" 1 10 || log_config_error "$(get_text configure.g-ssh-max-auth-tries-invalid-example-4 "${label_g}" "${G_SSH_MAX_AUTH_TRIES:-}")"
    check_port "${G_SSH_CLIENT_ALIVE_INTERVAL:-x}" 30 3600 || log_config_error "$(get_text configure.g-ssh-client-alive-interval-invalid-example-300 "${label_g}" "${G_SSH_CLIENT_ALIVE_INTERVAL:-}")"
    check_port "${G_SSH_CLIENT_ALIVE_COUNT_MAX:-x}" 1 10 || log_config_error "$(get_text configure.g-ssh-client-alive-count-max-invalid-example-2 "${label_g}" "${G_SSH_CLIENT_ALIVE_COUNT_MAX:-}")"
    check_port "${W_SSH_LOGIN_GRACE_TIME:-x}" 10 120 || log_config_error "$(get_text configure.w-ssh-login-grace-time-invalid-example-30 "${label_g}" "${W_SSH_LOGIN_GRACE_TIME:-}")"
    check_port "${W_PAM_PASSWORD_MIN_LENGTH:-x}" 8 32 || log_config_error "$(get_text configure.w-pam-password-min-length-invalid-example-12 "${label_g}" "${W_PAM_PASSWORD_MIN_LENGTH:-}")"
    check_port "${W_FAILLOCK_DENY:-x}" 3 20 || log_config_error "$(get_text configure.w-faillock-deny-invalid-example-8 "${label_g}" "${W_FAILLOCK_DENY:-}")"
    check_port "${W_FAILLOCK_UNLOCK:-x}" 60 86400 || log_config_error "$(get_text configure.w-faillock-unlock-invalid-example-600 "${label_g}" "${W_FAILLOCK_UNLOCK:-}")"
    check_port "${W_FAILLOCK_FAIL_INTERVAL:-x}" 60 86400 || log_config_error "$(get_text configure.w-faillock-fail-interval-invalid-example-900 "${label_g}" "${W_FAILLOCK_FAIL_INTERVAL:-}")"
    check_port "${G_WATCHDOG_CPU_LIMIT:-x}" 1 100 || log_config_error "$(get_text configure.g-watchdog-cpu-limit-invalid-example-50 "${label_g}" "${G_WATCHDOG_CPU_LIMIT:-}")"
    check_port "${G_WATCHDOG_LIMIT_NICE:-x}" 0 19 || log_config_error "$(get_text configure.g-watchdog-limit-nice-invalid-example-19 "${label_g}" "${G_WATCHDOG_LIMIT_NICE:-}")"
    check_port "${G_WATCHDOG_LIMIT_IO_NICE:-x}" 0 7 || log_config_error "$(get_text configure.g-watchdog-limit-io-nice-invalid-example-3 "${label_g}" "${G_WATCHDOG_LIMIT_IO_NICE:-}")"
    [[ "${G_MAIL_ALERTS:-}" =~ ^[01]$ ]] || log_config_error "$(get_text configure.g-mail-alerts-invalid-example-0-or-1 "${label_g}" "${G_MAIL_ALERTS:-}")"
    [[ "${G_RCLONE_ALERTS:-}" =~ ^[01]$ ]] || log_config_error "$(get_text configure.g-rclone-alerts-invalid-example-0-or-1 "${label_g}" "${G_RCLONE_ALERTS:-}")"
    if [[ "${G_RCLONE_ALERTS:-0}" == "1" || -n "${G_RCLONE_REMOTE:-}" ]]; then
        check_drive_remote "${G_RCLONE_REMOTE:-}" || log_config_error "$(get_text configure.g-rclone-remote-invalid-example-gdrive "${label_g}" "${G_RCLONE_REMOTE:-}")"
    fi
    if [[ "${G_RCLONE_ALERTS:-0}" == "1" || -n "${G_RCLONE_PATH:-}" ]]; then
        check_drive_path "${G_RCLONE_PATH:-}" || log_config_error "$(get_text configure.g-rclone-path-invalid-example-liltress-alerts "${label_g}" "${G_RCLONE_PATH:-}")"
    fi
    [[ "${G_MAIL_TEMPLATE:-mail.html}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.html$ ]] || log_config_error "$(get_text configure.g-mail-template-invalid-example-mail-html "${label_g}" "${G_MAIL_TEMPLATE:-}")"
    if [[ -n "${G_CONFIG_ROOT:-}" && -d "${G_CONFIG_ROOT}/template" && ! -f "${G_CONFIG_ROOT}/template/${G_MAIL_TEMPLATE:-mail.html}" ]]; then
        log_config_error "$(get_text configure.g-mail-template-not-found-example-a-file-html-of "${label_g}" "${G_MAIL_TEMPLATE:-mail.html}")"
    fi
    [[ "${G_CONFIG_BASE_DIRECTORY:-}" == "/opt/liltress-workstation" ]] || log_config_error "$(get_text configure.g-config-base-directory-invalid-example-opt-lilt "${label_g}" "${G_CONFIG_BASE_DIRECTORY:-}")"
    [[ "${G_SECRET_DIRECTORY:-}" == "/opt/liltress-workstation/secrets" ]] || log_config_error "$(get_text configure.g-secret-directory-invalid-example-opt-liltress "${label_g}" "${G_SECRET_DIRECTORY:-}")"

    [[ "${G_SECRET_PREPARED:-}" == "1" ]] || log_config_error "${label_s} : G_SECRET_PREPARED doit valoir 1. exemple : ./liltress configure"
    check_pro_token "${G_UBUNTU_PRO_TOKEN:-}" || log_config_error "$(get_text configure.g-ubuntu-pro-token-invalid-example-the-token-alp "${label_s}")"
    if [[ "${G_MAIL_ALERTS}" == "1" ]]; then
        check_email "${G_POSTFIX_SMTP_LOGIN:-}" || log_config_error "$(get_text configure.g-postfix-smtp-login-must-be-an-address-email-ex "${label_s}" "${G_POSTFIX_SMTP_LOGIN:-}")"
        check_email "${G_POSTFIX_MAIL_ADDRESS:-}" || log_config_error "$(get_text configure.g-postfix-mail-address-must-be-an-address-email "${label_s}" "${G_POSTFIX_MAIL_ADDRESS:-}")"
        check_app_password "${G_POSTFIX_MAIL_PASSWORD:-}" || log_config_error "$(get_text configure.g-postfix-mail-password-invalid-example-the-pass "${label_s}")"
        check_smtp "${G_POSTFIX_MAIL_SMTP:-}" || log_config_error "$(get_text configure.g-postfix-mail-smtp-invalid-example-smtp-mail-ou "${label_s}" "${G_POSTFIX_MAIL_SMTP:-}")"
        check_email "${G_WATCHDOG_MAIL:-}" || log_config_error "$(get_text configure.g-watchdog-mail-must-be-an-address-email-example "${label_s}" "${G_WATCHDOG_MAIL:-}")"
        [[ "${G_WATCHDOG_MAIL:-}" == "${G_POSTFIX_MAIL_ADDRESS:-}" ]] || log_config_error "$(get_text configure.g-watchdog-mail-must-be-the-same-address-that-g "${label_s}")"
    else
        [[ -z "${G_POSTFIX_SMTP_LOGIN:-}${G_POSTFIX_MAIL_ADDRESS:-}${G_POSTFIX_MAIL_PASSWORD:-}${G_POSTFIX_MAIL_SMTP:-}${G_WATCHDOG_MAIL:-}" ]] \
            || log_config_error "$(get_text configure.the-fields-e-mail-must-be-vides-when-the-alerts "${label_s}")"
    fi
}

require_prepared_config() {
    local root="$1"
    local g="${root}/config/global.conf"
    local s="${root}/config/secrets.conf"
    local mode src_count

    reset_config

    if [[ ! -f "${g}" ]]; then
        log_config_error "$(get_text configure.global-conf-absent-example-liltress-configures "${g}")"
    fi
    if [[ ! -f "${s}" ]]; then
        log_config_error "$(get_text configure.secrets-conf-absent-example-liltress-configures "${s}")"
    fi
    if [[ ! -f "${g}" || ! -f "${s}" ]]; then
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
    scan_config_dollar "${s}" "secrets.conf"

    src_count="$(grep -cE '(^|[[:space:]])(source|\.)[[:space:]]' "${g}" || true)"
    if [[ "${src_count}" != "1" ]] || ! grep -q 'source "${G_INSTALL_DIRECTORY}/config/secrets.conf"' "${g}"; then
        log_config_error "$(get_text configure.global-conf-the-only-command-source-allowed-load)"
    fi
    if grep -qE '(^|[[:space:]])(source|\.)[[:space:]]' "${s}"; then
        log_config_error "$(get_text configure.secrets-conf-no-command-source-example-only-of-t)"
    fi

    mode="$(stat -c '%a' "${s}" 2>/dev/null || echo '')"
    if [[ "${mode}" != "600" && "${mode}" != "400" ]]; then
        log_config_error "secrets.conf : permissions ${mode:-inconnues}, attendu 600. exemple : chmod 600 config/secrets.conf"
    fi

    if [[ ${#W_CONFIG_ERRORS[@]} -gt 0 ]]; then
        emit_config
        return 1
    fi

    set +u
    # shellcheck disable=SC1090
    source "${g}"
    # shellcheck disable=SC1090
    source "${s}"
    set -u

    G_CONFIG_ROOT="${root}"
    validate_values
    emit_config
}
