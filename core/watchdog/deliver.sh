#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/deliver.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================


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
    } > "${alert}" || true
}

log_alert() {
    local summary="$*"
    local excerpt="" module log alert line send base note="" note_cmd="" tool=""
    local hold_note="$(get_text alert.hold.note)"
    log="${LOG_FILE:-${LOG:-}}"
    alert="${ALERT_FILE:-}"
    excerpt="$(get_alert_excerpt "${log}")"
    line="$(printf '%s %s' "$(date -Iseconds)" "${summary}")"
    if [[ -n "${log}" ]]; then
        printf '%s\n' "${line}" | tee -a "${log}"
    else
        printf '%s\n' "${line}"
    fi
    module="${MODULE_NAME:-}"
    if [[ -z "${module}" && -n "${log}" ]]; then
        module="$(basename "${log}" | sed -E 's/-[0-9]{8}-.*//')"
    fi
    module="${module:-$(get_text alert.module.fallback)}"
    base="$(get_product_base)"
    ADVICE=""
    ADVICE_HOLD=0
    if take_quarantine_note; then
        note=""
        note_cmd=""
        ADVICE=""
        ADVICE_HOLD=0
    else
        if [[ "${AIDE_REFRESH:-}" == "1" ]]; then
            note="$(get_text alert.note.aide)"
            note_cmd="sudo bash ${base}/bin/aide-refresh-db.sh"
        elif [[ "${RKHUNTER_REFRESH:-}" == "1" ]]; then
            set_rkhunter_note
            note="${NOTE}"
            note_cmd="${NOTE_CMD}"
        elif [[ "${CHKROOTKIT_IGNORE:-}" == "1" && -n "${log}" ]]; then
            note="$(get_text alert.note.chkrootkit)"
            note_cmd="sudo bash ${base}/bin/chkrootkit-ignore-log.sh '${log}'"
        elif [[ "${DEBSUMS_IGNORE:-}" == "1" && -n "${log}" ]]; then
            note="$(get_text alert.note.debsums)"
            note_cmd="sudo bash ${base}/bin/debsums-ignore-log.sh '${log}'"
        fi
        if tool="$(get_alert_tool "${module}" "${log}" "${summary}")"; then
            render_alert_advice "${tool}" "${log}" "${summary}"
            if [[ "${ADVICE_HOLD:-0}" == "1" && -n "${note_cmd}" ]]; then
                note="${hold_note}"
            fi
        fi
    fi
    if [[ -z "${NOTE:-}" && -n "${note}" ]]; then
        NOTE="${note}"
        NOTE_CMD="${note_cmd}"
    fi
    if [[ "${ADVICE_HOLD:-0}" == "1" && -n "${NOTE_CMD:-}" ]]; then
        NOTE="${hold_note}"
    fi
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
    if [[ "${MAIL_ALERTS:-0}" == "1" && -n "${WATCHDOG_MAIL:-}" ]]; then
        send="$(send_path)" || true
        if [[ -n "${send}" ]]; then
            TITLE="${TITLE}" \
            MODULE_NAME="${module}" \
            CONTENT="${summary}

${excerpt}" \
            NOTE="${NOTE:-}" \
            NOTE_CMD="${NOTE_CMD:-}" \
            ADVICE="${ADVICE:-}" \
            WATCHDOG_MAIL="${WATCHDOG_MAIL}" \
            PROJECT_NAME="${PROJECT_NAME}" \
            MAIL_TEMPLATE="${MAIL_TEMPLATE:-mail.html}" \
                bash "${send}" || true
        fi
    fi
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

deliver_mail() {
    local script_dir detail _mail_sh _candidate tpl
    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[1]}")" && pwd)"
    detail="$(printf '%s' "${CONTENT:-}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [[ -z "${detail}" ]]; then
        echo "$(get_text watchdog.mail-not-sent-empty-body "${MODULE_NAME:-?}")" >&2
        exit 0
    fi
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
    export TITLE PROJECT_NAME HOSTNAME DATE MODULE_NAME CONTENT
    export NOTE="${NOTE:-}"
    export NOTE_CMD="${NOTE_CMD:-}"
    export ADVICE="${ADVICE:-}"
    _mail_sh=""
    for _candidate in \
        "${script_dir}/mail.sh" \
        "${CONFIG_BASE_DIRECTORY:-}/cron/bin/mail.sh" \
        "${CONFIG_BASE_DIRECTORY:-}/src/core/mail/mail.sh" \
        "${INSTALL_DIRECTORY:-}/core/mail/mail.sh" \
        "${INSTALL_DIRECTORY:-}/../share/core/mail/mail.sh" \
        "${script_dir}/../../../core/mail/mail.sh" \
        "${script_dir}/../../../../share/core/mail/mail.sh" \
        "${script_dir}/../share/core/mail/mail.sh" \
        "${script_dir}/../../core/mail/mail.sh" \
        "${script_dir}/../../src/core/mail/mail.sh"
    do
        if [[ -n "${_candidate}" && -f "${_candidate}" ]]; then
            _mail_sh="${_candidate}"
            break
        fi
    done
    if [[ -z "${_mail_sh}" ]]; then
        echo "$(get_text watchdog.mail-not-sent-core-mail-sh-not-found "${MODULE_NAME}")" >&2
        exit 0
    fi
    # shellcheck disable=SC1090
    source "${_mail_sh}"
    if [[ -n "${MAIL_TEMPLATE_FILE:-}" && -f "${MAIL_TEMPLATE_FILE}" ]]; then
        tpl="${MAIL_TEMPLATE_FILE}"
    else
        tpl="$(locate_mail_template "${script_dir}")" || {
            echo "$(get_text watchdog.mail-not-sent-template-html-not-found "${MODULE_NAME}")" >&2
            exit 0
        }
    fi
    if [[ "${MAIL_REDACT:-0}" == "1" ]]; then
        if ! MAIL_CONTENT="$(MAIL_REDACT=1 render_mail "${tpl}")"; then
            echo "$(get_text watchdog.mail-not-sent-template-html-invalid "${MODULE_NAME}")" >&2
            exit 0
        fi
    elif ! MAIL_CONTENT="$(render_mail "${tpl}")"; then
        echo "$(get_text watchdog.mail-not-sent-template-html-invalid "${MODULE_NAME}")" >&2
        exit 0
    fi
    if [[ -n "${HTML_REPORT:-}" ]]; then
        printf '%s\n' "${MAIL_CONTENT}" > "${HTML_REPORT}" || true
    fi
    if [[ "${MAIL_REQUIRE_FLAG:-0}" == "1" ]]; then
        if [[ "${MAIL_ALERTS:-0}" != "1" || -z "${WATCHDOG_MAIL:-}" ]]; then
            echo "$(get_text watchdog.mail-not-sent-alerts-e-mail-off "${MODULE_NAME:-?}")" >&2
            exit 0
        fi
    elif [[ -z "${WATCHDOG_MAIL:-}" ]]; then
        echo "$(get_text watchdog.mail-not-sent-destinataire-or-empty-body "${MODULE_NAME:-?}")" >&2
        exit 0
    fi
    if ! command -v mail >/dev/null 2>&1; then
        echo "$(get_text watchdog.mail-not-sent-command-mail-absent "${MODULE_NAME:-?}")" >&2
        exit 0
    fi
    local mail_type=()
    local mail_attach=()
    if mail --help 2>&1 | grep -q -- '--content-type'; then
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
