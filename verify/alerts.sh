#!/usr/bin/env bash
# =============================================================================
# File       : verify/alerts.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat << 'EOF'
Usage : sudo bash verify/alerts.sh [--no-send]

Contrôle la passe de démarrage qui envoie les alertes, la passe horaire, la passe différée,
ClamAV à l'accès, et le chemin du courrier. Sans --no-send, un seul message d'essai part
quand les alertes sont activées. Le sujet se termine par « Contrôle ».
EOF
    exit 0
fi

if [[ "${EUID}" -ne 0 ]]; then
    printf "$(get_text log.run-this-script-with-sudo-sudo-bash-verify-alert)" >&2
    exit 1
fi

send=1
if [[ "${1:-}" == "--no-send" ]]; then
    send=0
elif [[ -n "${1:-}" ]]; then
    printf 'Option inconnue : %s\n' "$1" >&2
    exit 2
fi

G_INSTALL_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export G_INSTALL_DIRECTORY
# shellcheck disable=SC1091
source "${G_INSTALL_DIRECTORY}/config/global.conf"

BASE="${G_CONFIG_BASE_DIRECTORY:-/opt/liltress-workstation}"
BIN="${BASE}/cron/bin"
LOG_DIR="${BASE}/cron/security_logs"
MAIL_CONF="${BASE}/cron/mail.conf"

if [[ -f "${MAIL_CONF}" ]]; then
    # shellcheck disable=SC1090
    source "${MAIL_CONF}"
fi
set -u

FAIL=0
WARN=0
REASONS=()

report_section() {
    printf '\n===== %s =====\n' "$1"
}

record_fail() {
    FAIL=$((FAIL + 1))
    REASONS+=("ECHEC   $*")
}

record_warn() {
    WARN=$((WARN + 1))
    REASONS+=("A_VOIR  $*")
}

record_pass() {
    printf "$(get_text log.ok ""$*"")"
}

check_unit_word() {
    local unit="$1"
    local active
    active="$(systemctl is-active "${unit}" 2>/dev/null || true)"
    case "${active}" in
        active) printf "$(get_text log.ok-2)" ;;
        inactive|failed|activating|deactivating) printf "$(get_text log.inactive)" ;;
        *) printf "$(get_text log.absent)" ;;
    esac
}

printf "$(get_text log.liltress-workstation-checks-that-send-an-alert-n)"
printf "$(get_text log.date-2 "$(date -Iseconds)")"
printf "$(get_text log.host "$(hostname -s 2>/dev/null || hostname)")"
printf "$(get_text log.base "${BASE}")"
if [[ "${G_MAIL_ALERTS:-0}" == "1" ]]; then
    printf "$(get_text log.alerts-enabled-n)"
else
    printf "$(get_text log.alerts-off-n)"
fi

report_section "PASSE AU DEMARRAGE"
timer_word="$(check_unit_word w-boot-chain.timer)"
printf "$(get_text log.36s ""w-boot-chain.timer"")" "${timer_word}"
[[ "${timer_word}" == "OK" ]] || record_fail "timer de la chaîne de démarrage ${timer_word}"
idle_word="$(check_unit_word w-idle-scan.timer)"
printf "$(get_text log.36s ""w-idle-scan.timer"")" "${idle_word}"
[[ "${idle_word}" == "OK" ]] || record_fail "timer de passe différée ${idle_word}"
periodic_word="$(check_unit_word w-periodic-scan.timer)"
printf "$(get_text log.36s ""w-periodic-scan.timer"")" "${periodic_word}"
[[ "${periodic_word}" == "OK" ]] || record_fail "timer d'analyse ClamAV périodique ${periodic_word}"
hourly_word="$(check_unit_word w-hourly-scan.timer)"
printf '%-36s %s\n' "w-hourly-scan.timer" "${hourly_word}"
[[ "${hourly_word}" == "OK" ]] || record_fail "timer de passe horaire ${hourly_word}"
if [[ -x "${BIN}/boot-scan.sh" ]] \
    && grep -q 'integrity.sh' "${BIN}/boot-scan.sh" \
    && grep -q 'behavior.sh' "${BIN}/boot-scan.sh" \
    && grep -q 'egress-watch.sh' "${BIN}/boot-scan.sh"; then
    record_pass "boot-scan.sh exécutable, avec intégrité, audit et journal sortant"
else
    record_fail "boot-scan.sh absent ou incomplet dans ${BIN}"
fi
if [[ -x "${BIN}/idle-scan.sh" ]]; then
    record_pass "idle-scan.sh exécutable"
else
    record_fail "idle-scan.sh absent de ${BIN}"
fi
skip_list="${BASE}/src/config/clamav/scan-skip.paths"
[[ -f "${skip_list}" ]] || skip_list="${BASE}/cron/scan-skip.paths"
if [[ -x "${BASE}/bin/scan-skip.sh" && -f "${skip_list}" ]]; then
    record_pass "commande scan-skip.sh et liste des chemins"
else
    record_fail "scan-skip.sh ou scan-skip.paths absent"
fi
printf '%-16s %-12s %s\n' "Module" "Script" "Lancé par"
for pair in "Aide aide.sh" "Rkhunter rkhunter.sh" "Chkrootkit chkrootkit.sh" "Clamav clamav.sh" "Debsums debsums.sh"; do
    label="${pair%% *}"
    script="${pair##* }"
    word="ABSENT"
    if [[ -x "${BIN}/${script}" ]]; then
        word="OK"
    elif [[ -f "${BIN}/${script}" ]]; then
        word="NON_EXEC"
    fi
    printf '%-16s %-12s %s\n' "${label}" "${word}" "démarrage"
    [[ "${word}" == "OK" ]] || record_fail "${label} : ${BIN}/${script} inutilisable"
done

if [[ -x "${BIN}/clamav-event.sh" ]] && grep -q 'clamav-event.sh' /etc/clamav/clamd.conf 2>/dev/null; then
    record_pass "ClamAV à l'accès : VirusEvent pointe vers clamav-event.sh"
else
    record_fail "ClamAV à l'accès : VirusEvent ou clamav-event.sh absent"
fi
if [[ -x "${BIN}/clamav-response.sh" ]]; then
    record_pass "réponse ClamAV exécutable"
else
    record_fail "clamav-response.sh absent de ${BIN}"
fi
if grep -q '^OnAccessIncludePath /tmp$' /etc/clamav/clamd.conf 2>/dev/null \
    && grep -q '^OnAccessIncludePath /var/tmp$' /etc/clamav/clamd.conf 2>/dev/null \
    && ! grep -q '^OnAccessIncludePath /$' /etc/clamav/clamd.conf 2>/dev/null \
    && ! grep -q '^OnAccessIncludePath /home$' /etc/clamav/clamd.conf 2>/dev/null; then
    record_pass "surveillance continue sur /tmp et /var/tmp, sans / ni /home"
else
    record_fail "surveillance continue incomplète"
fi
if grep -q '/var/lib/clamav/quarantine' /etc/clamav/clamd.conf 2>/dev/null \
    && grep -q '/var/lib/clamav/tmp' /etc/clamav/clamd.conf 2>/dev/null; then
    record_pass "quarantaine et temporaire ClamAV exclus"
else
    record_fail "quarantaine ou temporaire ClamAV non exclus"
fi

report_section "SERVICES"
clam_unit="clamav-clamonacc.service"
if [[ "$(check_unit_word clamonacc.service)" == "OK" ]]; then
    clam_unit="clamonacc.service"
fi
for unit in clamav-daemon.service clamav-freshclam.service "${clam_unit}" fail2ban.service auditd.service crowdsec.service crowdsec-firewall-bouncer.service; do
    word="$(check_unit_word "${unit}")"
    printf '%-36s %s\n' "${unit}" "${word}"
    [[ "${word}" == "OK" ]] || record_fail "service ${unit} ${word}"
done
if [[ "${G_MAIL_ALERTS:-0}" == "1" ]]; then
    word="$(check_unit_word postfix.service)"
    printf '%-36s %s\n' "postfix.service" "${word}"
    [[ "${word}" == "OK" ]] || record_fail "postfix ${word}"
else
    record_pass "postfix non exigé : alertes coupées"
fi
printf "$(get_text log.fail2ban-auditd-and-crowdsec-n-have-no-mail-clea)"

report_section "DERNIER PASSAGE"
if systemctl show w-boot-scan.service -p ExecMainExitTimestamp --value --no-pager 2>/dev/null | grep -q .; then
    printf "$(get_text log.last-start-of-the-password-s-n)" "$(systemctl show w-boot-scan.service -p ExecMainExitTimestamp --value --no-pager 2>/dev/null)"
    printf "$(get_text log.result-systemd-s-n)" "$(systemctl show w-boot-scan.service -p Result --value --no-pager 2>/dev/null)"
else
    record_warn "la passe de démarrage n'a pas encore de résultat systemd"
fi
printf '%-16s %-12s %s\n' "Module" "Journal" "Modifié"
for name in aide integrity rkhunter behavior chkrootkit clamav debsums egress; do
    file="$(find "${LOG_DIR}" -name "${name}-*.log" -type f 2>/dev/null | sort | tail -1 || true)"
    if [[ -n "${file}" ]]; then
        when="$(date -d "@$(stat -c %Y "${file}")" '+%Y-%m-%d %H:%M' 2>/dev/null || stat -c %y "${file}")"
        printf "$(get_text log.16s-12s "${name}")" "présent" "${when}"
    else
        printf "$(get_text log.16s-12s "${name}")" "absent" "pas encore de passage"
    fi
done

report_section "CHEMIN DU COURRIER"
if [[ -x "${BIN}/send.sh" ]]; then
    record_pass "send.sh exécutable"
else
    record_fail "send.sh absent de ${BIN}"
fi
if [[ -f "${BIN}/mail.html" || -f "${BIN}/template/mail.html" ]]; then
    record_pass "modèle HTML présent"
else
    record_fail "modèle HTML absent de ${BIN}"
fi
if command -v mail >/dev/null 2>&1; then
    record_pass "commande mail présente"
else
    record_fail "commande mail absente"
fi
if [[ "${G_MAIL_ALERTS:-0}" == "1" && -z "${G_WATCHDOG_MAIL:-}" ]]; then
    record_fail "alertes activées sans destinataire"
elif [[ "${G_MAIL_ALERTS:-0}" == "1" ]]; then
    record_pass "destinataire défini"
else
    record_pass "aucun destinataire exigé : alertes coupées"
fi

if [[ "${send}" -eq 0 ]]; then
    record_pass "essai non lancé (--no-send)"
elif [[ "${G_MAIL_ALERTS:-0}" != "1" ]]; then
    record_pass "essai non lancé : alertes coupées"
elif [[ "${FAIL}" -ne 0 ]]; then
    record_warn "essai non lancé : le chemin du courrier a déjà un échec"
else
    stamp="$(date +%Y%m%d-%H%M%S)"
    export DATE="$(date '+%Y-%m-%d %H:%M:%S')"
    export MODULE_NAME="Contrôle"
    export TITLE="Contrôle des alertes"
    export CONTENT="Contrôle Liltress Workstation. Ce message confirme que les alertes partent. Jeton ${stamp}."
    export NOTE=""
    export NOTE_CMD=""
    export G_PROJECT_NAME="${G_PROJECT_NAME:-Liltress Workstation}"
    export G_MAIL_TEMPLATE="${G_MAIL_TEMPLATE:-mail.html}"
    started="$(date +%s)"
    probe="$(bash "${BIN}/send.sh" 2>&1 || true)"
    if printf '%s\n' "${probe}" | grep -q 'Mail non envoyé'; then
        record_fail "essai refusé par send.sh"
        printf '%s\n' "${probe}" | sed -n '1,8p'
    else
        ack=""
        for _ in 1 2 3 4 5; do
            sleep 4
            ack="$(journalctl -u postfix --since "@${started}" --no-pager 2>/dev/null | grep -E 'status=(sent|deferred|bounced)' | tail -1 || true)"
            [[ -n "${ack}" ]] && break
        done
        if [[ "${ack}" == *status=sent* ]]; then
            record_pass "essai parti (status=sent, sujet se terminant par Contrôle)"
        elif [[ "${ack}" == *status=deferred* || "${ack}" == *status=bounced* ]]; then
            record_fail "essai non remis (SMTP deferred ou bounced)"
        elif [[ -z "$(mailq 2>/dev/null | sed -n '1p' | grep -v 'Mail queue is empty' || true)" ]]; then
            record_warn "essai accepté localement, accusé SMTP pas encore dans le journal"
        else
            record_fail "essai encore en file d'attente"
        fi
    fi
fi

if [[ "${#REASONS[@]}" -gt 0 ]]; then
    report_section "A CORRIGER"
    printf '%s\n' "${REASONS[@]}"
fi

report_section "RESULTAT"
if [[ "${FAIL}" -eq 0 && "${WARN}" -eq 0 ]]; then
    printf "$(get_text log.result-ok-n)"
    exit 0
fi
if [[ "${FAIL}" -eq 0 ]]; then
    printf "$(get_text log.result-ok-s-dot-s-to-confirmer-n)" "${WARN}"
    exit 0
fi
printf "$(get_text log.result-s-failure-s-s-dot-s-to-confirmer-n)" "${FAIL}" "${WARN}"
exit 1
