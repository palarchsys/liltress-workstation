#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/boot-check.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

set -u
W_BASE="${W_BASE:-/opt/liltress-workstation}"

if [[ "${EUID}" -ne 0 ]]; then
    printf "$(get_text log.run-this-command-with-sudo-n)" >&2
    exit 1
fi

ok_n=0
ecart_n=0
cours_n=0

record_boot_mark() {
    case "$1" in
        OK) ok_n=$((ok_n + 1)) ;;
        ECART) ecart_n=$((ecart_n + 1)) ;;
        EN_COURS) cours_n=$((cours_n + 1)) ;;
    esac
    printf "$(get_text log.10s "$1")" "$2"
}

get_millisecond() {
    python3 - "$1" << 'PY'
import sys
s = sys.argv[1].strip()
if s.endswith("ms"):
    print(int(round(float(s[:-2]))))
elif s.endswith("us"):
    print(int(round(float(s[:-2]) / 1000.0)))
elif s.endswith("s") and s != "infinity":
    print(int(round(float(s[:-1]) * 1000.0)))
else:
    print(0)
PY
}

nproc_n="$(nproc)"
limit=50
nice_want=19
global_conf=""
for candidate in \
    "${W_BASE}/src/config/global.conf" \
    "${W_BASE}/config/global.conf"
do
    if [[ -f "${candidate}" ]]; then
        global_conf="${candidate}"
        break
    fi
done
if [[ -n "${global_conf}" ]]; then
    value="$(grep -E '^G_WATCHDOG_CPU_LIMIT=' "${global_conf}" | tail -1 | cut -d= -f2-)"
    [[ "${value}" =~ ^[0-9]+$ ]] && limit="${value}"
    value="$(grep -E '^G_WATCHDOG_LIMIT_NICE=' "${global_conf}" | tail -1 | cut -d= -f2-)"
    [[ "${value}" =~ ^[0-9]+$ ]] && nice_want="${value}"
fi
want_pct=$((limit * nproc_n))
want_ms=$((want_pct * 10))
boot_epoch="$(date -d "$(uptime -s)" +%s 2>/dev/null || echo 0)"

printf "$(get_text log.host-date-start-nproc "$(hostname)" "$(date -Iseconds)" "$(uptime -s)" "${nproc_n}")"
printf "$(get_text log.expected-chain-after-multi-user-target-nice-io-i "${nice_want}" "${want_pct}")"
printf "$(get_text log.n)"

printf "$(get_text log.persistent-services-n)"
for unit in ssh clamav-daemon clamav-freshclam crowdsec crowdsec-firewall-bouncer fail2ban auditd apparmor unattended-upgrades unbound systemd-resolved; do
    enabled="$(systemctl is-enabled "${unit}" 2>/dev/null || echo absent)"
    active="$(systemctl is-active "${unit}" 2>/dev/null || echo absent)"
    if [[ "${active}" == "active" ]]; then
        record_boot_mark OK "${unit} enabled=${enabled} active=${active}"
    else
        record_boot_mark ECART "${unit} enabled=${enabled} active=${active}"
    fi
done
if systemctl is-active --quiet clamav-clamonacc.service || systemctl is-active --quiet clamonacc.service; then
    record_boot_mark OK "clamonacc actif"
else
    record_boot_mark ECART "clamonacc inactif"
fi
if systemctl is-active --quiet usbguard; then
    record_boot_mark OK "usbguard actif"
elif [[ -f /etc/usbguard/rules.conf ]] && ! grep -qF 'allow with-interface equals { 03:*:* }' /etc/usbguard/rules.conf; then
    record_boot_mark OK "usbguard arrêté : ligne clavier/souris absente"
else
    record_boot_mark ECART "usbguard inactif"
fi
ufw_line="$(ufw status 2>/dev/null | head -1 || true)"
if printf '%s' "${ufw_line}" | grep -Eqi 'inactive|inactif'; then
    record_boot_mark ECART "ufw ${ufw_line}"
elif printf '%s' "${ufw_line}" | grep -Eqi 'active|actif'; then
    record_boot_mark OK "ufw ${ufw_line}"
else
    record_boot_mark ECART "ufw ${ufw_line:-illisible}"
fi
if [[ -f "${W_BASE}/cron/mail.conf" ]] && grep -q '^G_MAIL_ALERTS="1"$' "${W_BASE}/cron/mail.conf"; then
    if systemctl is-active --quiet postfix; then
        record_boot_mark OK "postfix actif"
    else
        record_boot_mark ECART "postfix inactif"
    fi
else
    record_boot_mark OK "alertes e-mail coupées"
fi
root_login="$(sshd -T 2>/dev/null | awk 'tolower($1)=="permitrootlogin"{print tolower($2); exit}')"
password_auth="$(sshd -T 2>/dev/null | awk 'tolower($1)=="passwordauthentication"{print tolower($2); exit}')"
if [[ "${root_login}" == "no" && "${password_auth}" == "yes" ]]; then
    record_boot_mark OK "sshd PermitRootLogin=no PasswordAuthentication=yes"
else
    record_boot_mark ECART "sshd PermitRootLogin=${root_login:-?} PasswordAuthentication=${password_auth:-?}"
fi

printf '\n===== minuteries =====\n'
for timer in w-boot-chain w-idle-scan w-reboot-notice w-hourly-scan; do
    enabled="$(systemctl is-enabled "${timer}.timer" 2>/dev/null || echo absent)"
    active="$(systemctl is-active "${timer}.timer" 2>/dev/null || echo absent)"
    if [[ "${enabled}" == "enabled" && "${active}" == "active" ]]; then
        record_boot_mark OK "${timer}.timer"
    else
        record_boot_mark ECART "${timer}.timer enabled=${enabled} active=${active}"
    fi
done
if [[ -f /etc/systemd/system/w-boot-scan.timer ]]; then
    record_boot_mark ECART "w-boot-scan.timer encore présent"
else
    record_boot_mark OK "w-boot-scan.timer absent"
fi
if grep -q '^OnBootSec=' /etc/systemd/system/w-idle-scan.timer 2>/dev/null \
    || grep -q '^OnBootSec=' /etc/systemd/system/w-reboot-notice.timer 2>/dev/null; then
    record_boot_mark ECART "une minuterie répétée a encore OnBootSec"
else
    record_boot_mark OK "les répétitions n'ont pas de délai fixe au démarrage"
fi

printf '\n===== plafond CPU =====\n'
for unit in w-boot-scan w-idle-scan w-reboot-notice w-hourly-scan; do
    unit_file="/etc/systemd/system/${unit}.service"
    file_quota="$(grep -E '^CPUQuota=' "${unit_file}" 2>/dev/null | cut -d= -f2-)"
    file_nice="$(grep -E '^Nice=' "${unit_file}" 2>/dev/null | cut -d= -f2-)"
    file_io="$(grep -E '^IOSchedulingClass=' "${unit_file}" 2>/dev/null | cut -d= -f2-)"
    show_quota="$(systemctl show -p CPUQuotaPerSecUSec --value "${unit}.service")"
    got_ms="$(get_millisecond "${show_quota}")"
    show_io="$(systemctl show -p IOSchedulingClass --value "${unit}.service")"
    if [[ "${file_quota}" == "${want_pct}%" && "${file_nice}" == "${nice_want}" && "${file_io}" == "idle" \
        && "${got_ms}" == "${want_ms}" && ( "${show_io}" == "idle" || "${show_io}" == "3" ) ]]; then
        record_boot_mark OK "${unit} CPUQuota=${file_quota} effectif=${show_quota}"
    else
        record_boot_mark ECART "${unit} fichier=${file_quota:-absent} effectif=${show_quota:-absent} attendu=${want_pct}%"
    fi
done

chain_state="$(systemctl show -p ActiveState --value w-boot-chain.service)"
printf "$(get_text log.n-passes-of-this-start-n)"
if [[ "${chain_state}" == "active" || "${chain_state}" == "activating" ]]; then
    record_boot_mark EN_COURS "w-boot-chain.service état=${chain_state}"
else
    chain_result="$(systemctl show -p Result --value w-boot-chain.service)"
    chain_when="$(systemctl show -p ExecMainStartTimestamp --value w-boot-chain.service)"
    chain_epoch=0
    if [[ -n "${chain_when}" && "${chain_when}" != "n/a" ]]; then
        chain_epoch="$(date -d "${chain_when}" +%s 2>/dev/null || echo 0)"
    fi
    if [[ "${chain_epoch}" -ge "${boot_epoch}" && "${chain_result}" == "success" ]]; then
        record_boot_mark OK "w-boot-chain.service result=success début=${chain_when}"
    else
        record_boot_mark ECART "w-boot-chain.service result=${chain_result:-?} début=${chain_when:-jamais}"
    fi
fi

# A oneshot unit without a timer is unloaded: ExecMainStartTimestamp
# disappears and Result becomes success. This boot's journal keeps
# the job id, independent of language.
# 7d4958e8 start, 39f53479 success, be02cf68 or d9b373ed failure.
get_journal_mark() {
    local unit="$1"
    local rows last started when
    rows="$(journalctl -b -u "${unit}" --no-pager -o cat --output-fields=MESSAGE_ID \
        MESSAGE_ID=39f53479d3a045ac8e11786248231fbf \
        + -u "${unit}" MESSAGE_ID=be02cf6855d2428ba40df7e9d022f03d \
        + -u "${unit}" MESSAGE_ID=d9b373ed55a64feb8242e02dbe79a49c \
        2>/dev/null || true)"
    last="$(printf '%s\n' "${rows}" | grep -E '^[0-9a-f]{32}$' | tail -1 || true)"
    if [[ "${last}" == "39f53479d3a045ac8e11786248231fbf" ]]; then
        started="$(journalctl -b -u "${unit}" --no-pager -o short-iso -n 1 \
            MESSAGE_ID=7d4958e842da4a758f6c1cdc7b36dcc5 2>/dev/null | head -1 || true)"
        when="journal"
        if [[ "${started}" =~ ^[0-9]{4}- ]]; then
            when="${started%% *}"
        fi
        record_boot_mark OK "${unit} result=success début=${when} (journal)"
        return 0
    fi
    if [[ "${last}" == "be02cf6855d2428ba40df7e9d022f03d" || "${last}" == "d9b373ed55a64feb8242e02dbe79a49c" ]]; then
        record_boot_mark ECART "${unit} échec dans le journal de ce démarrage"
        return 0
    fi
    if [[ "${chain_state}" == "active" || "${chain_state}" == "activating" ]]; then
        record_boot_mark EN_COURS "${unit} pas encore lancé par la chaîne"
        return 0
    fi
    record_boot_mark ECART "${unit} pas lancé depuis ce démarrage"
}

check_boot_unit() {
    local unit="$1"
    local state result when epoch
    state="$(systemctl show -p ActiveState --value "${unit}")"
    if [[ "${state}" == "active" || "${state}" == "activating" ]]; then
        record_boot_mark EN_COURS "${unit} état=${state}"
        return 0
    fi
    result="$(systemctl show -p Result --value "${unit}")"
    when="$(systemctl show -p ExecMainStartTimestamp --value "${unit}")"
    epoch=0
    if [[ -n "${when}" && "${when}" != "n/a" ]]; then
        epoch="$(date -d "${when}" +%s 2>/dev/null || echo 0)"
    fi
    if [[ "${epoch}" -lt "${boot_epoch}" ]]; then
        get_journal_mark "${unit}"
        return 0
    fi
    if [[ "${result}" == "success" ]]; then
        record_boot_mark OK "${unit} result=success début=${when}"
    else
        record_boot_mark ECART "${unit} result=${result:-?} début=${when}"
    fi
}

check_boot_unit w-boot-scan.service
check_boot_unit w-idle-scan.service
check_boot_unit w-reboot-notice.service

printf "$(get_text log.n-journals-since-this-start-n)"

get_latest_log() {
    find "${W_BASE}/cron/security_logs" -maxdepth 1 -type f -name "$1-*.log" -newermt "$(uptime -s)" -printf '%T@ %p\n' 2>/dev/null \
        | sort -n | tail -1 | cut -d' ' -f2-
}

for name in aide integrity rkhunter behavior chkrootkit clamav debsums egress idle-scan reboot-notice; do
    log_file="$(get_latest_log "${name}")"
    if [[ -z "${log_file}" ]]; then
        if [[ "${chain_state}" == "active" || "${chain_state}" == "activating" ]]; then
            record_boot_mark EN_COURS "${name} : journal pas encore écrit"
        else
            record_boot_mark ECART "${name} : aucun journal depuis le démarrage"
        fi
        continue
    fi
    last_line="$(grep -E '.' "${log_file}" | tail -1 || true)"
    if [[ -z "${last_line}" ]]; then
        record_boot_mark ECART "${name} $(basename "${log_file}") vide"
    elif printf '%s' "${last_line}" | grep -Eq 'planté|erreur rc='; then
        record_boot_mark ECART "${name} $(basename "${log_file}") | ${last_line}"
    else
        record_boot_mark OK "${name} $(basename "${log_file}") | ${last_line}"
    fi
done

printf "$(get_text log.n)"
if [[ "${ecart_n}" -eq 0 && "${cours_n}" -eq 0 ]]; then
    printf "$(get_text log.check-of-start-ok-n)"
    exit 0
fi
if [[ "${ecart_n}" -eq 0 ]]; then
    printf "$(get_text log.check-of-start-in-progress-n)"
    exit 1
fi
printf "$(get_text log.check-of-start-carts-n)"
exit 1
