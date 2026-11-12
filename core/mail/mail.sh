#!/usr/bin/env bash
# =============================================================================
# File       : core/mail/mail.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================


locate_python_dir() {
    local dir hops=0
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        if [[ -d "${dir}/share/python" ]]; then
            printf '%s\n' "${dir}/share/python"
            return 0
        fi
        if [[ -d "${dir}/python" ]]; then
            printf '%s\n' "${dir}/python"
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

check_mail_template_name() {
    [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.html$ ]]
}

log_mail_fatal() {
    if declare -F log_error >/dev/null 2>&1; then
        log_error "${INSTALL_WATCHER:-BASH}" "install.mail.error" "$*"
    fi
    printf '%s\n' "$*" >&2
    exit 1
}

install_mail_templates() {
    local dest="$1"
    local src="${INSTALL_DIRECTORY:?}/template"
    local chosen="${MAIL_TEMPLATE:-mail.html}"
    local f base n=0
    local nullglob_was=0
    [[ -d "${dest}" ]] || log_mail_fatal "$(get_text mail.directory-of-installation-of-the-mod-les-absent "${dest}")"
    [[ -d "${src}" ]] || log_mail_fatal "$(get_text mail.directory-template-absent "${src}")"
    check_mail_template_name "${chosen}" || log_mail_fatal "$(get_text mail.g-mail-template-invalid-example-mail-html "${chosen}")"

    if shopt -q nullglob; then
        nullglob_was=1
    fi
    shopt -s nullglob
    for f in "${src}/"*.html; do
        base="$(basename -- "${f}")"
        check_mail_template_name "${base}" || log_mail_fatal "$(get_text mail.name-of-template-denied-example-mail-html "${base}")"
        cp -f -- "${f}" "${dest}/${base}"
        chmod 644 "${dest}/${base}"
        n=$((n + 1))
    done
    if [[ "${nullglob_was}" -eq 0 ]]; then
        shopt -u nullglob
    fi
    [[ "${n}" -ge 1 ]] || log_mail_fatal "$(get_text mail.no-file-html-in "${src}")"
    [[ -f "${dest}/${chosen}" ]] || log_mail_fatal "$(get_text mail.template-absent-of "${chosen}" "${src}")"
}

get_mail_name() {
    local here="${1:-}"
    local conf line
    local -a confs=()
    [[ -n "${INSTALL_DIRECTORY:-}" ]] && confs+=("${INSTALL_DIRECTORY}/config/global.conf")
    [[ -n "${CONFIG_BASE_DIRECTORY:-}" ]] && confs+=("${CONFIG_BASE_DIRECTORY}/src/config/global.conf")
    if [[ -n "${here}" ]]; then
        confs+=(
            "${here}/../../src/config/global.conf"
            "${here}/../../../config/global.conf"
            "${here}/../config/global.conf"
        )
    fi
    for conf in "${confs[@]}"; do
        [[ -f "${conf}" ]] || continue
        line="$(awk -F= '/^MAIL_TEMPLATE=/{gsub(/"/,"",$2); gsub(/[[:space:]]/,"",$2); print $2; exit}' "${conf}")"
        if [[ -n "${line}" ]]; then
            printf '%s\n' "${line}"
            return 0
        fi
    done
    if [[ -n "${MAIL_TEMPLATE:-}" ]]; then
        printf '%s\n' "${MAIL_TEMPLATE}"
        return 0
    fi
    printf '%s\n' "mail.html"
}

locate_mail_template() {
    local here="${1:-}"
    local name dir
    local -a dirs=()
    name="$(get_mail_name "${here}")"
    check_mail_template_name "${name}" || return 1
    [[ -n "${INSTALL_DIRECTORY:-}" ]] && dirs+=("${INSTALL_DIRECTORY}/template")
    [[ -n "${CONFIG_BASE_DIRECTORY:-}" ]] && dirs+=("${CONFIG_BASE_DIRECTORY}/src/template")
    if [[ -n "${here}" ]]; then
        dirs+=(
            "${here}/../../src/template"
            "${here}/../../../template"
            "${here}/../template"
            "${here}"
            "${here}/../../service/cron/watchdogs"
        )
    fi
    for dir in "${dirs[@]}"; do
        if [[ -f "${dir}/${name}" ]]; then
            printf '%s\n' "${dir}/${name}"
            return 0
        fi
    done
    return 1
}

render_mail() {
    local template="$1"
    local mail_here="" mail_candidate=""
    local mail_module="" mail_redacted="" mail_redacted_key="" mail_unreadable="" mail_no_pre=""
    [[ -f "${template}" ]] || return 1
    if ! declare -F get_text >/dev/null 2>&1; then
        mail_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
        for mail_candidate in \
            "${mail_here}/log.sh" \
            "${PRODUCT_ROOT:-}/core/log/log.sh" \
            "${INSTALL_DIRECTORY:-}/core/log/log.sh" \
            "${INSTALL_DIRECTORY:-}/src/core/log/log.sh"
        do
            if [[ -n "${mail_candidate}" && -f "${mail_candidate}" ]]; then
                # shellcheck disable=SC1090
                source "${mail_candidate}"
                break
            fi
        done
    fi
    if declare -F get_text >/dev/null 2>&1; then
        load_text "${LANGUAGE:-en}"
        mail_module="$(get_text mail.module)"
        mail_read="$(get_text mail.read)"
        mail_seen="$(get_text mail.seen)"
        mail_check="$(get_text mail.check)"
        mail_next="$(get_text mail.next)"
        mail_redacted="$(get_text mail.redacted)"
        mail_redacted_key="$(get_text mail.redacted-key)"
        mail_unreadable="$(get_text mail.template-unreadable)"
        mail_no_pre="$(get_text mail.template-no-pre)"
    else
        mail_module="Module:"
        mail_read="The journal is at the top. Each finding then shows the command, a normal example, and a worrying example."
        mail_seen="Journal"
        mail_check="How to read the finding"
        mail_next="What to do next"
        mail_redacted="[redacted]"
        mail_redacted_key="[private key redacted]"
        mail_unreadable="unreadable template: {1}"
        mail_no_pre="template without a pre tag"
    fi
    MAIL_TEMPLATE_FILE="${template}" \
    MAIL_REDACT="${MAIL_REDACT:-0}" \
    MAIL_LANG="${LANGUAGE:-en}" \
    MAIL_MODULE="${mail_module}" \
    MAIL_READ="${mail_read}" \
    MAIL_SEEN="${mail_seen}" \
    MAIL_CHECK="${mail_check}" \
    MAIL_NEXT="${mail_next}" \
    TEXT_REDACTED="${mail_redacted}" \
    TEXT_REDACTED_KEY="${mail_redacted_key}" \
    TEXT_TEMPLATE_UNREADABLE="${mail_unreadable}" \
    TEXT_TEMPLATE_NO_PRE="${mail_no_pre}" \
    python3 "$(locate_python_dir)/mail-render.py"
}

apply_postfix() {
    local line key value host
    host="$(hostname -f)"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" || "${line}" == \#* ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        value="${value//__HOSTNAME__/${host}}"
        value="${value//__RELAYHOST__/${relayhost}}"
        value="${value//__PROJECT_NAME__/${PROJECT_NAME}}"
        value="${value//__SASL_TYPE__/${sasl_type}}"
        postconf -e "${key} = ${value}"
    done < "$(locate_config_file postfix/main.keys)"
}

send_install_mail() {
    local detail="" cred_file="" tpl=""
    local about=""
    if ! declare -F get_text >/dev/null 2>&1; then
        # shellcheck disable=SC1091
        source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
        # shellcheck disable=SC1091
        source "${INSTALL_DIRECTORY}/config/global.conf"
    fi
    DATE="$(date '+%Y-%m-%d %H:%M:%S')"
    HOSTNAME="${HOSTNAME:-$(hostname -s 2>/dev/null || hostname)}"
    case "${MODULE_NAME:-}" in
        Aide) about="$(get_text log.integrity-of-the-files-watched-by-help-help-chec)" ;;
        Chkrootkit) about="Recherche de rootkits (chkrootkit -x -q)." ;;
        Rkhunter) about="$(get_text log.search-of-rootkits-and-files-changed-rkhunter-ch)" ;;
        Clamav) about="$(get_text log.files-reported-by-clamav-quarantine-and-journals)" ;;
        Auditd) about="$(get_text log.events-of-audit-abnormal-ausearch)" ;;
        Debsums) about="$(get_text log.files-of-packages-whose-the-checksum-a-changed-d)" ;;
        Fail2ban) about="$(get_text log.bans-fail2ban-of-the-derni-res-24-h)" ;;
        Crowdsec) about="$(get_text log.decisions-and-alerts-crowdsec-of-the-derni-res-2)" ;;
        Ufw) about="$(get_text log.packages-blocked-by-ufw)" ;;
        "Matrix Credentials") about="$(get_text log.credentials-matrix-element-and-postgres-created)" ;;
        "Keycloak Credentials") about="Identifiants Keycloak et client du portail." ;;
        "Livekit Credentials") about="Identifiants LiveKit (SFU et service de jetons)." ;;
        "Wireguard Credentials") about="Identifiants du VPN wg-easy." ;;
        "Users Credentials") about="$(get_text log.account-ssh-and-key-created-to-the-installation)" ;;
        "Nginx htpasswd") about="$(get_text log.password-of-the-zone-of-administration-nginx)" ;;
        *) about="Message du module ${MODULE_NAME:-inconnu}." ;;
    esac
    detail="$(printf '%s' "${CONTENT:-}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [[ -z "${detail}" ]]; then
        echo "$(get_text watchdog.mail-not-sent-empty-body "${MODULE_NAME:-?}")" >&2
        return 0
    fi
    CONTENT="${about}

${detail}"
    export TITLE PROJECT_NAME HOSTNAME DATE MODULE_NAME CONTENT
    tpl="$(locate_mail_template "${INSTALL_DIRECTORY:-}")" || {
        echo "$(get_text watchdog.mail-not-sent-template-html-not-found "${MODULE_NAME}")" >&2
        return 0
    }
    if ! MAIL_CONTENT="$(render_mail "${tpl}")"; then
        echo "$(get_text watchdog.mail-not-sent-template-html-invalid "${MODULE_NAME}")" >&2
        return 0
    fi
    if [[ "${MAIL_ALERTS:-0}" != "1" ]]; then
        cred_file="/root/liltress-credentials.txt"
        umask 077
        {
            printf '\n----- %s — %s -----\n' "${DATE}" "${MODULE_NAME:-message}"
            printf '%s\n' "${MAIL_CONTENT}"
        } >> "${cred_file}"
        chmod 600 "${cred_file}"
        printf "$(get_text log.credentials-saved-in-s-n)" "${cred_file}"
        return 0
    fi
    echo "${MAIL_CONTENT}" | mail -s "${OBJECT}" \
        -a "Content-Type: text/html; charset=UTF-8" \
        "${WATCHDOG_MAIL}"
}
