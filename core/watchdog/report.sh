#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/report.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Fill the mail blocks of one watchdog alert.
# Note       : Crash sentences keep the existing mail template.
# -----------------------------------------------------------------------------


get_watchdog_phase() {
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
take_service_name() {
    local tool="$1"
    local name="$2"
    if [[ -z "${tool}" || "${tool}" == "-" ]]; then
        printf '%s' "${name}"
        return 0
    fi
    printf '%s' "${tool}"
}

record_service() {
    local state_directory="$1"
    local service="$2"
    [[ -n "${service}" && "${service}" != "-" ]] || return 0
    [[ "${seen}" == *"|${service}|"* ]] && return 0
    printf '%s\n' "${service}" >>"${state_directory}/services.txt"
    seen="${seen}${service}|"
}

render_watchdog_row() {
    local state_directory="$1"
    local explained="$2"
    local hold="$3"
    local name="$5"
    local when="$6"
    local path="$7"
    local tool="$8"
    local class_id="$9"
    [[ "${explained}" == "0" ]] || return 0
    record_service "${state_directory}" "$(take_service_name "${tool}" "${name}")"
    if [[ -n "${path}" && "${path}" != "-" ]]; then
        set_watchdog_when "${path}"
        printf '%s - %s\n' "${when}" "${path}" >>"${state_directory}/files.txt"
    fi
}

render_watchdog_rows() {
    local state_directory="$1"
    local explained="" hold="" kind="" name="" when="" path="" tool="" class_id=""
    local seen="|"
    : >"${state_directory}/services.txt"
    : >"${state_directory}/files.txt"
    [[ -f "${state_directory}/rows.tsv" ]] || return 0
    while IFS=$'\t' read -r explained hold kind name when path tool class_id; do
        render_watchdog_row "${state_directory}" "${explained}" "${hold}" "${kind}" "${name}" \
            "${when}" "${path}" "${tool}" "${class_id}"
    done <"${state_directory}/rows.tsv"
}

get_watchdog_block() {
    local file_path="$1"
    if [[ -s "${file_path}" ]]; then
        cat -- "${file_path}"
    fi
}

# One real row for this tool is enough.
read_watchdog_tool_hit() {
    local state_directory="$1"
    local tool="$2"
    local row_explained="" row_hold="" row_kind="" row_name="" row_when="" row_path="" row_tool="" row_class=""
    while IFS=$'\t' read -r row_explained row_hold row_kind row_name row_when row_path row_tool row_class; do
        [[ "${row_explained}" == "0" && "${row_tool}" == "${tool}" ]] || continue
        printf '%s\n' "yes"
        return 0
    done <"${state_directory}/rows.tsv"
    return 1
}

get_watchdog_ignore_commands() {
    local state_directory="$1"
    local base="" tool="" found=""
    base="$(get_product_base)"
    [[ -f "${state_directory}/rows.tsv" ]] || return 0
    for tool in aide rkhunter; do
        found="$(read_watchdog_tool_hit "${state_directory}" "${tool}")" || true
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

get_mail_service_label() {
    case "$1" in
        aide) printf 'AIDE' ;;
        rkhunter) printf 'RKHunter' ;;
        clamav) printf 'ClamAV' ;;
        chkrootkit) printf 'Chkrootkit' ;;
        debsums) printf 'Debsums' ;;
        auditd) printf 'Auditd' ;;
        fail2ban) printf 'Fail2ban' ;;
        crowdsec) printf 'CrowdSec' ;;
        ufw) printf 'UFW' ;;
        fingerprint) printf 'Fingerprint' ;;
        *) printf '%s' "$1" ;;
    esac
}

get_mail_services_label() {
    local file="$1"
    local line label joined=""
    [[ -f "${file}" ]] || return 0
    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        label="$(get_mail_service_label "${line}")"
        if [[ -n "${joined}" ]]; then
            joined="${joined}, ${label}"
        else
            joined="${label}"
        fi
    done <"${file}"
    printf '%s' "${joined}"
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
    local state_directory="$1"
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
    MAIL_SERVICES="$(get_watchdog_block "${state_directory}/services.txt")"
    MAIL_FILES="$(get_watchdog_block "${state_directory}/files.txt")"
    MAIL_ACTIONS="$(get_watchdog_block "${state_directory}/actions.txt")"
    MAIL_IGNORE="$(get_watchdog_ignore_commands "${state_directory}")"
    take_watchdog_content
}

send_watchdog_report() {
    local phase="$1"
    local state_directory="$2"
    local zip_path="${3:-}"
    local title="" here="" template=""
    here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    locate_alert_template "${here}"
    load_text "${LANGUAGE:-en}"
    take_watchdog_title "${phase}"
    render_watchdog_rows "${state_directory}"
    MAIL_SERVICE="$(get_mail_services_label "${state_directory}/services.txt")"
    set_watchdog_mail "${state_directory}" "${title}"
    MAIL_TEMPLATE_FILE="${template}"
    MAIL_ATTACH="${zip_path}"
    export TITLE MODULE_NAME PROJECT_NAME HOSTNAME DATE CONTENT MAIL_SERVICE
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
    local state_directory="$2"
    local log="$3"
    local zip_path=""
    apply_watchdog_remedy "${phase}" "${state_directory}"
    refresh_watchdog_rows "${state_directory}" || true
    render_watchdog_rows "${state_directory}"
    mkdir -p -- "${state_directory}/logs"
    cp -f -- "${log}" "${state_directory}/logs/"
    zip_path="$(write_watchdog_pack "${phase}" "${state_directory}" "${state_directory}/logs")"
    send_watchdog_report "${phase}" "${state_directory}" "${zip_path}"
}

finish_watchdog_status() {
    local status="$1"
    local phase="$2"
    local state_directory="$3"
    local log="$4"
    case "${status}" in
        clean)
            rm -rf -- "${state_directory}"
            return 0
            ;;
        false)
            refresh_watchdog_rows "${state_directory}" || true
            rm -rf -- "${state_directory}"
            return 0
            ;;
        real)
            report_real_watchdog "${phase}" "${state_directory}" "${log}"
            rm -rf -- "${state_directory}"
            return 0
            ;;
        *)
            rm -rf -- "${state_directory}"
            return 1
            ;;
    esac
}

report_watchdog_module() {
    local module="$1"
    local log="$2"
    local summary="$3"
    local tool="" phase="" state_directory="" status=""
    if [[ "${summary}" =~ planté|crashed|abgestürzt|bloqueó|erreur\ rc=|error\ rc=|did\ not\ finish|n.est\ pas\ allé\ au\ bout ]]; then
        return 1
    fi
    if ! tool="$(get_alert_tool "${module}" "${log}" "${summary}" 2>/dev/null)"; then
        take_report_tool "${module}" || return 1
    fi
    phase="$(get_watchdog_phase "${tool}" "$(basename -- "${log:-}")")" || return 1
    state_directory="$(mktemp -d)"
    status="$(check_watchdog_phase "${phase}" "${log}" "0" "" "${state_directory}")"
    finish_watchdog_status "${status}" "${phase}" "${state_directory}" "${log}"
}
