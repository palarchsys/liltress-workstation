#!/usr/bin/env bash
# =============================================================================
# File       : service/postfix/configure.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY
G_INSTALL_DIRECTORY="${INSTALL_DIRECTORY}"
export G_INSTALL_DIRECTORY

source "${G_INSTALL_DIRECTORY}/core/lib.sh"
source "${G_INSTALL_DIRECTORY}/config/global.conf"
require_root

if [[ "${G_MAIL_ALERTS:-0}" != "1" ]]; then
    log_info         "${INSTALL_WATCHER}" "configure.alerts-email-off-postfix-is-not-configured"
    exit 0
fi

log_subtitle     "${INSTALL_WATCHER}" "configure.credentials-smtp"
log_info         "${INSTALL_WATCHER}" "configure.record-of-the-card-sasl"
relay_host="${G_POSTFIX_MAIL_SMTP%:*}"
relay_port="${G_POSTFIX_MAIL_SMTP##*:}"
relayhost="[${relay_host}]:${relay_port}"
install -d -m 755 /etc/postfix
umask 077
printf '%s %s:%s\n' "${relayhost}" "${G_POSTFIX_SMTP_LOGIN}" "${G_POSTFIX_MAIL_PASSWORD}" \
    > /etc/postfix/sasl_passwd
umask 022
sasl_type="$(get_sasl_map_type)"
case "${sasl_type}" in
    hash) sasl_index="/etc/postfix/sasl_passwd.db" ;;
    cdb) sasl_index="/etc/postfix/sasl_passwd.cdb" ;;
    lmdb) sasl_index="/etc/postfix/sasl_passwd.lmdb" ;;
esac
run_silent       "${INSTALL_WATCHER}" "configure.postfix.error" postmap "${sasl_type}:/etc/postfix/sasl_passwd"
if [[ ! -f "${sasl_index}" ]]; then
    log_error        "${INSTALL_WATCHER}" "configure.card-sasl-absent-after-postmap"
fi
chmod 600 /etc/postfix/sasl_passwd "${sasl_index}"
log_success      "${INSTALL_WATCHER}" "configure.card-sasl-saved-reading-root-only"

log_subtitle     "${INSTALL_WATCHER}" "configure.name-of-mail"
log_info         "${INSTALL_WATCHER}" "configure.configuration-of-the-name-of-mail"
printf '%s\n' "$(hostname -f)" > /etc/mailname
chmod 644 /etc/mailname
log_success      "${INSTALL_WATCHER}" "configure.mailname-saved" "$(hostname -f)"

log_subtitle     "${INSTALL_WATCHER}" "configure.relay-and-rewrite-of-the-sender"
log_info         "${INSTALL_WATCHER}" "configure.configuration-of-the-relay-and-of-the-sender"
printf '/.*/ %s\n' "${G_POSTFIX_MAIL_ADDRESS}" > /etc/postfix/sender_canonical
chmod 644 /etc/postfix/sender_canonical

apply_postfix() {
    local line key value host
    host="$(hostname -f)"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" || "${line}" == \#* ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        value="${value//__HOSTNAME__/${host}}"
        value="${value//__RELAYHOST__/${relayhost}}"
        value="${value//__PROJECT_NAME__/${G_PROJECT_NAME}}"
        value="${value//__SASL_TYPE__/${sasl_type}}"
        postconf -e "${key} = ${value}"
    done < "$(locate_config_file postfix/main.keys)"
}
apply_postfix
log_success      "${INSTALL_WATCHER}" "configure.local-sender-rewritten-all-part-as" "${G_POSTFIX_MAIL_ADDRESS}"

log_info         "${INSTALL_WATCHER}" "configure.restart-of-postfix"
run_silent       "${INSTALL_WATCHER}" "configure.postfix.error" systemctl restart postfix
if ! systemctl is-active --quiet postfix; then
    log_error        "${INSTALL_WATCHER}" "configure.postfix-is-not-active-after-the-configuration"
fi
log_success      "${INSTALL_WATCHER}" "configure.postfix-enabled-listens-limited-to-localhost"
