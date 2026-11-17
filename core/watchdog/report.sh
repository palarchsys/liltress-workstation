#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/report.sh
# Updated at : 2026-11-17
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Fill the mail blocks of one watchdog alert.
# Note       : Crash sentences keep the existing mail template.
# -----------------------------------------------------------------------------


watchdog_phase_of() {
    local tool="$1"
    local log_name="$2"
    case "${log_name}" in
        *event*)
            printf '%s\n' evergreen
            return 0
            ;;
    esac
    case "${tool}" in
        clamav | chkrootkit | rkhunter) printf '%s\n' malware ;;
        debsums | auditd | aide) printf '%s\n' integrity ;;
        crowdsec | fail2ban) printf '%s\n' evergreen ;;
        *) return 1 ;;
    esac
}

# The caller owns when. A missing time becomes the file time, or the clock time.
set_watchdog_when() {
    local path="$1"
    if [[ -n "${when}" && "${when}" != "-" ]]; then
        return 0
    fi
    if [[ -e "${path}" ]]; then
        when="$(date -r "${path}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')"
        return 0
    fi
    when="$(date '+%Y-%m-%d %H:%M:%S')"
}

# One real row becomes one service line and maybe one file line.
render_watchdog_row() {
    local state_dir="$1"
    local explained="$2"
    local hold="$3"
    local kind="$4"
    local name="$5"
    local when="$6"
    local path="$7"
    local tool="$8"
    local class_id="$9"
    local type_word=""
    [[ "${explained}" == "0" ]] || return 0
    case "${kind}" in
        package) type_word="$(get_text alert.mail.type.package)" ;;
        jail) type_word="$(get_text alert.mail.type.jail)" ;;
        scenario) type_word="$(get_text alert.mail.type.scenario)" ;;
        *) type_word="$(get_text alert.mail.type.file)" ;;
    esac
    if [[ "${seen}" != *"|${type_word} - ${name}|"* ]]; then
        printf '%s - %s\n' "${type_word}" "${name}" >>"${state_dir}/services.txt"
        seen="${seen}${type_word} - ${name}|"
    fi
    if [[ -n "${path}" && "${path}" != "-" ]]; then
        set_watchdog_when "${path}"
        printf '%s - %s\n' "${when}" "${path}" >>"${state_dir}/files.txt"
    fi
}

render_watchdog_rows() {
    local state_dir="$1"
    local explained="" hold="" kind="" name="" when="" path="" tool="" class_id=""
    local seen="|"
    : >"${state_dir}/services.txt"
    : >"${state_dir}/files.txt"
    [[ -f "${state_dir}/rows.tsv" ]] || return 0
    while IFS=$'\t' read -r explained hold kind name when path tool class_id; do
        render_watchdog_row "${state_dir}" "${explained}" "${hold}" "${kind}" "${name}" \
            "${when}" "${path}" "${tool}" "${class_id}"
    done <"${state_dir}/rows.tsv"
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
        done <"${state_dir}/rows.tsv"
        [[ "${found}" == "yes" ]] || continue
        case "${tool}" in
            aide)
                printf '%s\n' "$(get_text alert.mail.ignore.command "sudo bash ${base}/service/aide/refresh-db.sh")"
                ;;
            rkhunter)
                printf '%s\n' "$(get_text alert.mail.ignore.command "sudo bash ${base}/service/rkhunter/refresh-db.sh")"
                ;;
        esac
    done
}

# The caller owns template. The first existing template is kept.
locate_alert_template() {
    local here="$1"
    local candidate=""
    template=""
    for candidate in \
        "${here}/../../template/mail-alert.html" \
        "${here}/../../../template/mail-alert.html" \
        "${BASE:-}/template/mail-alert.html" \
        "${CONFIG_BASE_DIRECTORY:-}/template/mail-alert.html"; do
        if [[ -f "${candidate}" ]]; then
            template="${candidate}"
            return 0
        fi
    done
    return 0
}

# The caller owns title.
take_watchdog_title() {
    local phase="$1"
    case "${phase}" in
        integrity) title="$(get_text alert.mail.integrity.title)" ;;
        evergreen) title="$(get_text alert.mail.evergreen.title)" ;;
        *) title="$(get_text alert.mail.malware.title)" ;;
    esac
}

# The caller owns CONTENT. The first filled block becomes the plain body.
take_watchdog_content() {
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
}

set_watchdog_mail() {
    local state_dir="$1"
    local title="$2"
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
    take_watchdog_content
}

send_watchdog_report() {
    local phase="$1"
    local state_dir="$2"
    local zip_path="${3:-}"
    local title="" here="" template=""
    here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    locate_alert_template "${here}"
    load_text "${LANGUAGE:-en}"
    take_watchdog_title "${phase}"
    render_watchdog_rows "${state_dir}"
    set_watchdog_mail "${state_dir}" "${title}"
    MAIL_TEMPLATE_FILE="${template}"
    MAIL_ATTACH="${zip_path}"
    export TITLE MODULE_NAME PROJECT_NAME HOSTNAME DATE CONTENT
    export MAIL_SUBTITLE MAIL_FOOTER MAIL_BLOCK_SERVICES MAIL_BLOCK_FILES MAIL_BLOCK_ACTIONS MAIL_BLOCK_IGNORE
    export MAIL_SERVICES MAIL_FILES MAIL_ACTIONS MAIL_IGNORE MAIL_TEMPLATE_FILE MAIL_ATTACH
    (deliver_mail) || true
}

# The caller owns tool. Known modules keep a fixed tool name.
take_report_tool() {
    local module="$1"
    case "${module}" in
        Debsums | debsums) tool="debsums" ;;
        Auditd | auditd) tool="auditd" ;;
        Fail2ban | fail2ban) tool="fail2ban" ;;
        Crowdsec | crowdsec) tool="crowdsec" ;;
        *) return 1 ;;
    esac
    return 0
}

# A real phase is repaired, packed, and mailed.
report_real_watchdog() {
    local phase="$1"
    local state_dir="$2"
    local log="$3"
    local zip_path=""
    apply_watchdog_remedy "${phase}" "${state_dir}"
    refresh_watchdog_rows "${state_dir}" || true
    render_watchdog_rows "${state_dir}"
    mkdir -p -- "${state_dir}/logs"
    cp -f -- "${log}" "${state_dir}/logs/"
    zip_path="$(write_watchdog_pack "${phase}" "${state_dir}" "${state_dir}/logs")"
    send_watchdog_report "${phase}" "${state_dir}" "${zip_path}"
}

finish_watchdog_status() {
    local status="$1"
    local phase="$2"
    local state_dir="$3"
    local log="$4"
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
            report_real_watchdog "${phase}" "${state_dir}" "${log}"
            rm -rf -- "${state_dir}"
            return 0
            ;;
        *)
            rm -rf -- "${state_dir}"
            return 1
            ;;
    esac
}

report_watchdog_module() {
    local module="$1"
    local log="$2"
    local summary="$3"
    local tool="" phase="" state_dir="" status=""
    if [[ "${summary}" =~ planté|crashed|abgestürzt|bloqueó|erreur\ rc=|error\ rc=|did\ not\ finish|n.est\ pas\ allé\ au\ bout ]]; then
        return 1
    fi
    if ! tool="$(get_alert_tool "${module}" "${log}" "${summary}" 2>/dev/null)"; then
        take_report_tool "${module}" || return 1
    fi
    phase="$(watchdog_phase_of "${tool}" "$(basename -- "${log:-}")")" || return 1
    state_dir="$(mktemp -d)"
    status="$(check_watchdog_phase "${phase}" "${log}" "0" "" "${state_dir}")"
    finish_watchdog_status "${status}" "${phase}" "${state_dir}" "${log}"
}
