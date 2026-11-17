#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/deliver.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Place one alert on disk and hand the HTML mail to the local mail program.
# Note       : An empty body or a missing address leaves the process with status 0.
# Note       : Help text picks the HTML header. A zip is attached when that file is present.
# -----------------------------------------------------------------------------


write_alert_file() {
    local alert="$1" summary="$2" excerpt="$3" advice="$4" note="$5" note_cmd="$6"
    local dir
    [[ -n "${alert}" ]] || return 0
    dir="$(dirname -- "${alert}")"
    mkdir -p "${dir}" 2>/dev/null || true
    {
        printf '%s\n' "${summary}"
        if [[ -n "${excerpt}" ]]; then
            printf '\n%s\n' "${excerpt}"
        fi
        if [[ -n "${advice}" ]]; then
            printf '\n%s\n' "${advice}"
        fi
        if [[ -n "${note}" ]]; then
            printf '\n%s\n' "${note}"
        fi
        if [[ -n "${note_cmd}" ]]; then
            printf '\n%s\n' "${note_cmd}"
        fi
    } >"${alert}" || true
}

# The dated line is copied into the journal when one is open.
record_alert_line() {
    local line="$1"
    local log="$2"
    if [[ -n "${log}" ]]; then
        printf '%s\n' "${line}" | tee -a "${log}"
    else
        printf '%s\n' "${line}"
    fi
}

# A missing module name is taken from the journal name, then from the catalog.
take_alert_module() {
    local module="$1"
    local log="$2"
    if [[ -z "${module}" && -n "${log}" ]]; then
        module="$(basename "${log}" | sed -E 's/-[0-9]{8}-.*//')"
    fi
    if [[ -z "${module}" ]]; then
        module="$(get_text alert.module.fallback)"
    fi
    printf '%s' "${module}"
}

# The caller owns note and note_cmd. Only one baseline command is kept.
apply_alert_refresh_note() {
    local base="$1"
    local log="$2"
    if [[ "${AIDE_REFRESH:-}" == "1" ]]; then
        note="$(get_text alert.note.aide)"
        note_cmd="sudo bash ${base}/service/aide/refresh-db.sh"
        return 0
    fi
    if [[ "${RKHUNTER_REFRESH:-}" == "1" ]]; then
        set_rkhunter_note
        note="${NOTE}"
        note_cmd="${NOTE_CMD}"
        return 0
    fi
    if [[ "${CHKROOTKIT_IGNORE:-}" == "1" && -n "${log}" ]]; then
        note="$(get_text alert.note.chkrootkit)"
        note_cmd="sudo bash ${base}/service/chkrootkit/ignore-log.sh '${log}'"
        return 0
    fi
    if [[ "${DEBSUMS_IGNORE:-}" == "1" && -n "${log}" ]]; then
        note="$(get_text alert.note.debsums)"
        note_cmd="sudo bash ${base}/service/debsums/ignore-log.sh '${log}'"
        return 0
    fi
    return 0
}

# Advice replaces the note when the class must stay on hold.
apply_alert_advice() {
    local module="$1"
    local log="$2"
    local summary="$3"
    local hold_note="$4"
    local tool=""
    if tool="$(get_alert_tool "${module}" "${log}" "${summary}")"; then
        render_alert_advice "${tool}" "${log}" "${summary}"
        if [[ "${ADVICE_HOLD:-0}" == "1" && -n "${note_cmd}" ]]; then
            note="${hold_note}"
        fi
    fi
}

# The caller owns NOTE. A hold class replaces the command note.
publish_alert_note() {
    local hold_note="$1"
    if [[ -z "${NOTE:-}" && -n "${note}" ]]; then
        NOTE="${note}"
        NOTE_CMD="${note_cmd}"
    fi
    if [[ "${ADVICE_HOLD:-0}" == "1" && -n "${NOTE_CMD:-}" ]]; then
        NOTE="${hold_note}"
    fi
}

# The direct branch keeps the recipient in the environment.
invoke_alert_shell() {
    local send="$1"
    TITLE="${TITLE}" \
        MODULE_NAME="${2}" \
        CONTENT="${3}

${4}" \
        NOTE="${NOTE:-}" \
        NOTE_CMD="${NOTE_CMD:-}" \
        ADVICE="${ADVICE:-}" \
        WATCHDOG_MAIL="${WATCHDOG_MAIL}" \
        PROJECT_NAME="${PROJECT_NAME}" \
        MAIL_TEMPLATE="${MAIL_TEMPLATE:-mail.html}" \
        bash "${send}" || true
}

# The root branch uses sudo and leaves the recipient out.
invoke_alert_sudo() {
    local send="$1"
    TITLE="${TITLE}" \
        MODULE_NAME="${2}" \
        CONTENT="${3}

${4}" \
        NOTE="${NOTE:-}" \
        NOTE_CMD="${NOTE_CMD:-}" \
        ADVICE="${ADVICE:-}" \
        PROJECT_NAME="${PROJECT_NAME}" \
        MAIL_TEMPLATE="${MAIL_TEMPLATE:-mail.html}" \
        MAIL_ALERTS="${MAIL_ALERTS}" \
        CONFIG_BASE_DIRECTORY="${CONFIG_BASE_DIRECTORY:-}" \
        BASE="${BASE:-}" \
        sudo -n -- "${send}" || true
}

# Mail stays off unless alerts are enabled and a sender script exists.
send_alert_mail() {
    local send=""
    local module="$1"
    local summary="$2"
    local excerpt="$3"
    [[ "${MAIL_ALERTS:-0}" == "1" ]] || return 0
    send="$(send_path)" || true
    if [[ -z "${send}" ]]; then
        return 0
    fi
    if [[ -n "${WATCHDOG_MAIL:-}" || "${EUID}" -eq 0 ]]; then
        invoke_alert_shell "${send}" "${module}" "${summary}" "${excerpt}"
        return 0
    fi
    invoke_alert_sudo "${send}" "${module}" "${summary}" "${excerpt}"
}

log_alert() {
    local summary="$*"
    local excerpt="" module="" log="" alert="" line="" base="" note="" note_cmd=""
    local hold_note="$(get_text alert.hold.note)"
    log="${LOG_FILE:-${LOG:-}}"
    alert="${ALERT_FILE:-}"
    excerpt="$(get_alert_excerpt "${log}")"
    line="$(printf '%s %s' "$(date -Iseconds)" "${summary}")"
    record_alert_line "${line}" "${log}"
    module="$(take_alert_module "${MODULE_NAME:-}" "${log}")"
    base="$(get_product_base)"
    ADVICE=""
    ADVICE_HOLD=0
    if take_quarantine_note; then
        note=""
        note_cmd=""
        ADVICE=""
        ADVICE_HOLD=0
    else
        apply_alert_refresh_note "${base}" "${log}"
        apply_alert_advice "${module}" "${log}" "${summary}" "${hold_note}"
    fi
    publish_alert_note "${hold_note}"
    if [[ -z "${TITLE:-}" ]]; then
        TITLE="$(get_text alert.title.module "${module}")"
    fi
    if [[ -z "${PROJECT_NAME:-}" ]]; then
        PROJECT_NAME="Liltress"
    fi
    write_alert_file "${alert}" "${summary}" "${excerpt}" "${ADVICE:-}" "${NOTE:-}" "${NOTE_CMD:-}"
    if [[ "${WATCHDOG_HOLD_MAIL:-0}" == "1" ]]; then
        return 0
    fi
    if declare -F report_watchdog_module >/dev/null 2>&1; then
        if report_watchdog_module "${module}" "${log}" "${summary}"; then
            return 0
        fi
    fi
    send_alert_mail "${module}" "${summary}" "${excerpt}"
}

render_mail_about() {
    case "${MODULE_NAME:-}" in
        Aide) printf '%s\n' "$(get_text log.integrity-of-the-files-watched-by-help-help-chec)" ;;
        Chkrootkit) printf '%s\n' "$(get_text watchdog.about.chkrootkit)" ;;
        Rkhunter) printf '%s\n' "$(get_text log.search-of-rootkits-and-files-changed-rkhunter-ch)" ;;
        Clamav) printf '%s\n' "$(get_text log.files-reported-by-clamav-quarantine-and-journals)" ;;
        Auditd) printf '%s\n' "$(get_text log.events-of-audit-abnormal-ausearch)" ;;
        Debsums) printf '%s\n' "$(get_text log.files-of-packages-whose-the-checksum-a-changed-d)" ;;
        Fail2ban) printf '%s\n' "$(get_text log.bans-fail2ban-of-the-derni-res-24-h)" ;;
        Crowdsec) printf '%s\n' "$(get_text log.decisions-and-alerts-crowdsec-of-the-derni-res-2)" ;;
        Ufw) printf '%s\n' "$(get_text log.packages-blocked-by-ufw)" ;;
        Reboot) printf '%s\n' "$(get_text watchdog.a-restart-is-useful-the-machine-was-not-restarte)" ;;
        *) printf '%s\n' "$(get_text watchdog.about.module "${MODULE_NAME:-$(get_text watchdog.module.unknown)}")" ;;
    esac
}

# The caller owns CONTENT. The about line is placed above the trimmed body.
set_mail_detail() {
    local detail="$1"
    if [[ "${MAIL_ABOUT:-0}" == "1" ]]; then
        CONTENT="$(render_mail_about)

${detail}"
    else
        CONTENT="${detail}"
    fi
    HOSTNAME="$(hostname -s 2>/dev/null || hostname)"
    DATE="${DATE:-$(date '+%Y-%m-%d %H:%M:%S')}"
    TITLE="${TITLE:-$(get_text alert.title.short)}"
    MODULE_NAME="${MODULE_NAME:-$(get_text alert.module.mail)}"
    if [[ -z "${PROJECT_NAME:-}" ]]; then
        PROJECT_NAME="Liltress"
    fi
}

# The caller owns mail_script. The first existing file is kept.
locate_mail_engine() {
    local script_dir="$1"
    local candidate=""
    mail_script=""
    for candidate in \
        "${script_dir}/mail.sh" \
        "${CONFIG_BASE_DIRECTORY:-}/core/mail/mail.sh" \
        "${INSTALL_DIRECTORY:-}/core/mail/mail.sh" \
        "${INSTALL_DIRECTORY:-}/../share/core/mail/mail.sh" \
        "${script_dir}/../../../core/mail/mail.sh" \
        "${script_dir}/../../../../share/core/mail/mail.sh" \
        "${script_dir}/../share/core/mail/mail.sh" \
        "${script_dir}/../../core/mail/mail.sh" \
        "${script_dir}/../../core/mail/mail.sh"; do
        if [[ -n "${candidate}" && -f "${candidate}" ]]; then
            mail_script="${candidate}"
            return 0
        fi
    done
    return 0
}

# A bad template stops the process with status 0.
render_alert_html() {
    local tpl="$1"
    if [[ "${MAIL_REDACT:-0}" == "1" ]]; then
        if ! MAIL_CONTENT="$(MAIL_REDACT=1 render_mail "${tpl}")"; then
            echo "$(get_text watchdog.mail-not-sent-template-html-invalid "${MODULE_NAME}")" >&2
            exit 0
        fi
        return 0
    fi
    if ! MAIL_CONTENT="$(render_mail "${tpl}")"; then
        echo "$(get_text watchdog.mail-not-sent-template-html-invalid "${MODULE_NAME}")" >&2
        exit 0
    fi
    return 0
}

# A missing address or a missing mail program stops the process with status 0.
skip_mail_delivery() {
    if [[ "${MAIL_REQUIRE_FLAG:-0}" == "1" ]]; then
        if [[ "${MAIL_ALERTS:-0}" != "1" || -z "${WATCHDOG_MAIL:-}" ]]; then
            echo "$(get_text watchdog.mail-not-sent-alerts-e-mail-off "${MODULE_NAME:-?}")" >&2
            exit 0
        fi
        return 0
    fi
    if [[ -z "${WATCHDOG_MAIL:-}" ]]; then
        echo "$(get_text watchdog.mail-not-sent-destinataire-or-empty-body "${MODULE_NAME:-?}")" >&2
        exit 0
    fi
    if ! command -v mail >/dev/null 2>&1; then
        echo "$(get_text watchdog.mail-not-sent-command-mail-absent "${MODULE_NAME:-?}")" >&2
        exit 0
    fi
    return 0
}

# Help text picks the HTML header. A zip is attached when the file is present.
send_html_mail() {
    local mail_help=""
    local -a mail_type=()
    local -a mail_attach=()
    mail_help="$(bash -c 'mail --help' 2>&1 || true)"
    if printf '%s\n' "${mail_help}" | grep -q -- '--content-type'; then
        mail_type+=(--content-type="text/html; charset=UTF-8")
    else
        mail_type+=(-a "Content-Type: text/html; charset=UTF-8")
    fi
    if [[ -n "${MAIL_ATTACH:-}" && -f "${MAIL_ATTACH}" ]]; then
        mail_attach+=(-A "${MAIL_ATTACH}")
    fi
    printf '%s\n' "${MAIL_CONTENT}" | mail -s "${PROJECT_NAME} - ${HOSTNAME} - ${MODULE_NAME}" \
        "${mail_type[@]}" \
        "${mail_attach[@]}" \
        "${WATCHDOG_MAIL}"
}

deliver_mail() {
    local script_dir="" detail="" tpl="" mail_script=""
    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[1]}")" && pwd)"
    detail="$(printf '%s' "${CONTENT:-}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [[ -z "${detail}" ]]; then
        echo "$(get_text watchdog.mail-not-sent-empty-body "${MODULE_NAME:-?}")" >&2
        exit 0
    fi
    set_mail_detail "${detail}"
    export TITLE PROJECT_NAME HOSTNAME DATE MODULE_NAME CONTENT
    export NOTE="${NOTE:-}"
    export NOTE_CMD="${NOTE_CMD:-}"
    export ADVICE="${ADVICE:-}"
    locate_mail_engine "${script_dir}"
    if [[ -z "${mail_script}" ]]; then
        echo "$(get_text watchdog.mail-not-sent-core-mail-sh-not-found "${MODULE_NAME}")" >&2
        exit 0
    fi
    # shellcheck disable=SC1090
    source "${mail_script}"
    if [[ -n "${MAIL_TEMPLATE_FILE:-}" && -f "${MAIL_TEMPLATE_FILE}" ]]; then
        tpl="${MAIL_TEMPLATE_FILE}"
    else
        tpl="$(locate_mail_template "${script_dir}")" || {
            echo "$(get_text watchdog.mail-not-sent-template-html-not-found "${MODULE_NAME}")" >&2
            exit 0
        }
    fi
    render_alert_html "${tpl}"
    if [[ -n "${HTML_REPORT:-}" ]]; then
        printf '%s\n' "${MAIL_CONTENT}" >"${HTML_REPORT}" || true
    fi
    skip_mail_delivery
    send_html_mail
}
