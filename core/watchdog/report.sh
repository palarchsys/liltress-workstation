#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/report.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

# -----------------------------------------------------------------------------
# Purpose    : Fill the mail blocks and send one watchdog report.
# Note       : Crash sentences keep the existing mail template.
# -----------------------------------------------------------------------------

watchdog_phase_of() {
    local tool="$1"
    local log_name="$2"
    case "${log_name}" in
        *event*) printf '%s\n' evergreen; return 0 ;;
    esac
    case "${tool}" in
        clamav|chkrootkit|rkhunter) printf '%s\n' malware ;;
        debsums|auditd|aide) printf '%s\n' integrity ;;
        crowdsec|fail2ban) printf '%s\n' evergreen ;;
        *) return 1 ;;
    esac
}

render_watchdog_rows() {
    local state_dir="$1"
    local row explained hold kind name when path tool class_id
    local type_word services="" files="" seen="|"
    : > "${state_dir}/services.txt"
    : > "${state_dir}/files.txt"
    [[ -f "${state_dir}/rows.tsv" ]] || return 0
    while IFS=$'\t' read -r explained hold kind name when path tool class_id; do
        [[ "${explained}" == "0" ]] || continue
        case "${kind}" in
            package) type_word="$(get_text alert.mail.type.package)" ;;
            jail) type_word="$(get_text alert.mail.type.jail)" ;;
            scenario) type_word="$(get_text alert.mail.type.scenario)" ;;
            *) type_word="$(get_text alert.mail.type.file)" ;;
        esac
        if [[ "${seen}" != *"|${type_word} - ${name}|"* ]]; then
            printf '%s - %s\n' "${type_word}" "${name}" >> "${state_dir}/services.txt"
            seen="${seen}${type_word} - ${name}|"
        fi
        if [[ -n "${path}" && "${path}" != "-" ]]; then
            if [[ -z "${when}" || "${when}" == "-" ]]; then
                if [[ -e "${path}" ]]; then
                    when="$(date -r "${path}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')"
                else
                    when="$(date '+%Y-%m-%d %H:%M:%S')"
                fi
            fi
            printf '%s - %s\n' "${when}" "${path}" >> "${state_dir}/files.txt"
        fi
    done < "${state_dir}/rows.tsv"
}

watchdog_block() {
    local file_path="$1"
    if [[ -s "${file_path}" ]]; then
        cat -- "${file_path}"
    fi
}

watchdog_ignore_commands() {
    local state_dir="$1"
    local base="" tool="" found=""
    local row_explained="" row_hold="" row_kind="" row_name="" row_when="" row_path="" row_tool="" row_class=""
    base="$(get_product_base)"
    [[ -f "${state_dir}/rows.tsv" ]] || return 0
    for tool in aide rkhunter; do
        found=""
        while IFS=$'\t' read -r row_explained row_hold row_kind row_name row_when row_path row_tool row_class; do
            [[ "${row_explained}" == "0" && "${row_tool}" == "${tool}" ]] || continue
            found="yes"
            break
        done < "${state_dir}/rows.tsv"
        [[ "${found}" == "yes" ]] || continue
        case "${tool}" in
            aide)
                printf '%s\n' "$(get_text alert.mail.ignore.command "sudo bash ${base}/bin/aide-refresh-db.sh")"
                ;;
            rkhunter)
                printf '%s\n' "$(get_text alert.mail.ignore.command "sudo bash ${base}/bin/rkhunter-refresh-db.sh")"
                ;;
        esac
    done
}

send_watchdog_report() {
    local phase="$1"
    local state_dir="$2"
    local zip_path="${3:-}"
    local title here template
    here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    template=""
    for template in \
        "${here}/../../service/cron/watchdogs/mail-alert.html" \
        "${BASE:-}/cron/bin/mail-alert.html" \
        "${CONFIG_BASE_DIRECTORY:-}/cron/bin/mail-alert.html"
    do
        [[ -f "${template}" ]] && break
        template=""
    done
    load_text "${LANGUAGE:-en}"
    case "${phase}" in
        integrity) title="$(get_text alert.mail.integrity.title)" ;;
        evergreen) title="$(get_text alert.mail.evergreen.title)" ;;
        *) title="$(get_text alert.mail.malware.title)" ;;
    esac
    render_watchdog_rows "${state_dir}"
    if [[ -z "${PROJECT_NAME:-}" ]]; then
        PROJECT_NAME="Liltress"
    fi
    HOSTNAME="$(hostname -s 2>/dev/null || hostname)"
    DATE="$(date '+%Y-%m-%d %H:%M:%S')"
    TITLE="${title}"
    MODULE_NAME="${title}"
    MAIL_SUBTITLE="${PROJECT_NAME} • ${HOSTNAME} • ${DATE}"
    MAIL_FOOTER="${PROJECT_NAME}"
    MAIL_BLOCK_SERVICES="$(get_text alert.mail.services)"
    MAIL_BLOCK_FILES="$(get_text alert.mail.files)"
    MAIL_BLOCK_ACTIONS="$(get_text alert.mail.actions)"
    MAIL_BLOCK_IGNORE="$(get_text alert.mail.ignore)"
    MAIL_SERVICES="$(watchdog_block "${state_dir}/services.txt")"
    MAIL_FILES="$(watchdog_block "${state_dir}/files.txt")"
    MAIL_ACTIONS="$(watchdog_block "${state_dir}/actions.txt")"
    MAIL_IGNORE="$(watchdog_ignore_commands "${state_dir}")"
    CONTENT="${MAIL_SERVICES}"
    if [[ -z "${CONTENT}" ]]; then
        CONTENT="${MAIL_FILES}"
    fi
    if [[ -z "${CONTENT}" ]]; then
        CONTENT="${MAIL_ACTIONS}"
    fi
    if [[ -z "${CONTENT}" ]]; then
        CONTENT="${MAIL_IGNORE}"
    fi
    MAIL_TEMPLATE_FILE="${template}"
    MAIL_ATTACH="${zip_path}"
    export TITLE MODULE_NAME PROJECT_NAME HOSTNAME DATE CONTENT
    export MAIL_SUBTITLE MAIL_FOOTER MAIL_BLOCK_SERVICES MAIL_BLOCK_FILES MAIL_BLOCK_ACTIONS MAIL_BLOCK_IGNORE
    export MAIL_SERVICES MAIL_FILES MAIL_ACTIONS MAIL_IGNORE MAIL_TEMPLATE_FILE MAIL_ATTACH
    ( deliver_mail ) || true
}

report_watchdog_module() {
    local module="$1"
    local log="$2"
    local summary="$3"
    local tool="" phase="" state_dir="" status="" zip_path=""
    if [[ "${summary}" =~ planté|crashed|abgestürzt|bloqueó|erreur\ rc=|error\ rc=|did\ not\ finish|n.est\ pas\ allé\ au\ bout ]]; then
        return 1
    fi
    if ! tool="$(get_alert_tool "${module}" "${log}" "${summary}" 2>/dev/null)"; then
        case "${module}" in
            Debsums|debsums) tool="debsums" ;;
            Auditd|auditd) tool="auditd" ;;
            Fail2ban|fail2ban) tool="fail2ban" ;;
            Crowdsec|crowdsec) tool="crowdsec" ;;
            *) return 1 ;;
        esac
    fi
    phase="$(watchdog_phase_of "${tool}" "$(basename -- "${log:-}")")" || return 1
    state_dir="$(mktemp -d)"
    status="$(check_watchdog_phase "${phase}" "${log}" "0" "" "${state_dir}")"
    case "${status}" in
        clean)
            rm -rf -- "${state_dir}"
            return 0
            ;;
        false)
            refresh_watchdog_rows "${state_dir}" || true
            rm -rf -- "${state_dir}"
            return 0
            ;;
        real)
            apply_watchdog_remedy "${phase}" "${state_dir}"
            refresh_watchdog_rows "${state_dir}" || true
            render_watchdog_rows "${state_dir}"
            mkdir -p -- "${state_dir}/logs"
            cp -f -- "${log}" "${state_dir}/logs/"
            zip_path="$(write_watchdog_pack "${phase}" "${state_dir}" "${state_dir}/logs")"
            send_watchdog_report "${phase}" "${state_dir}" "${zip_path}"
            rm -rf -- "${state_dir}"
            return 0
            ;;
        *)
            rm -rf -- "${state_dir}"
            return 1
            ;;
    esac
}
