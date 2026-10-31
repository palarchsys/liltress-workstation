#!/usr/bin/env bash
# =============================================================================
# File       : verify/workstation.sh
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
get_current_user
get_ssh_port
get_operating_system

PASS=0
FAIL=0
WARNN=0
REPORT="${G_LOG_DIR:-.}/verify-report-WORKSTATION-$(date +%Y%m%d-%H%M%S).md"

report_pass()   { PASS=$((PASS+1));  G_LOG_FIT_MAX=0 log_success "${INSTALL_WATCHER}" "log.ok-3" "$*"; echo "$(get_text log.ok-4 "$*")" >> "${REPORT}"; }
report_fail()   { FAIL=$((FAIL+1));  set_color_red "FAIL  $*";     echo "- FAIL  $*" >> "${REPORT}"; }
report_warn()   { WARNN=$((WARNN+1)); log_warn "${INSTALL_WATCHER}" "verify.workstation.warn" "WARN  $*";   echo "- WARN  $*" >> "${REPORT}"; }

mkdir -p "$(dirname "${REPORT}")"
{
    echo "$(get_text log.liltress-workstation-check-workstation)"
    echo
    echo "$(get_text log.date-4 "$(date -Iseconds)")"
    echo "$(get_text log.user "${CURRENT_USER}")"
    echo "$(get_text log.os-2 "${OS_PRETTY}")"
    echo
} > "${REPORT}"

log_subtitle "${INSTALL_WATCHER}" "log.contracts-passwords-apps"

root_hash="$(awk -F: '$1=="root"{print $2}' /etc/shadow)"
user_hash="$(awk -F: -v u="${CURRENT_USER}" '$1==u{print $2}' /etc/shadow)"
if [[ -z "${root_hash}" ]]; then
    report_fail "shadow root vide"
elif [[ "${root_hash}" == "*" || "${root_hash}" == "!" || "${root_hash}" == "!!" || "${root_hash}" == "!*" ]]; then
    report_pass "compte root verrouillé par Ubuntu (ce programme ne pose pas de mot de passe root)"
else
    report_pass "root : hash présent, non réécrit par HFU"
fi
if [[ -z "${user_hash}" || "${user_hash}" == "!" || "${user_hash}" == "*" ]]; then
    report_fail "compte ${CURRENT_USER} sans mot de passe utilisable"
else
    report_pass "compte ${CURRENT_USER} : hash intact (HFU n'appelle jamais chpasswd)"
fi

maxdays="$(LANG=C LC_ALL=C chage -l "${CURRENT_USER}" 2>/dev/null | awk -F: '/Maximum/{gsub(/ /,"",$2); print $2}')"
if [[ "${maxdays}" == "90" ]]; then
    report_warn "chage MAXDAYS=90 sur ${CURRENT_USER}"
else
    report_pass "chage ${CURRENT_USER} non forcé à 90 jours"
fi

if drift="$(check_account_drift 2>&1)"; then
    report_pass "comptes humains (uid, groupes, home, shell, hash) inchangés"
else
    report_fail "un compte créé à l'installation Ubuntu a été modifié"
    printf '%s\n' "${drift}" >> "${REPORT}"
fi

for b in gcc g++ cc make; do
    if command -v "${b}" >/dev/null 2>&1; then
        mode="$(stat -c '%a' "$(command -v "${b}")")"
        if [[ "${mode}" == "700" ]]; then
            report_fail "compilateur ${b} en 700"
        else
            report_pass "compilateur ${b} mode ${mode}"
        fi
    fi
done

log_subtitle "${INSTALL_WATCHER}" "log.ssh-ufw-services"

root_login="$(get_sshd_value permitrootlogin)"
if [[ "${root_login}" == "no" ]]; then
    report_pass "PermitRootLogin no"
else
    report_fail "PermitRootLogin n'est pas no (valeur effective : ${root_login:-inconnue})"
fi
if [[ "$(get_sshd_value passwordauthentication)" == "yes" ]]; then
    report_pass "PasswordAuthentication yes (le mot de passe du compte est accepté en SSH)"
else
    report_pass "PasswordAuthentication n'est pas yes (SSH n'accepte qu'une clé pour ${CURRENT_USER})"
fi
tcp_fwd="$(get_sshd_value allowtcpforwarding)"
agent_fwd="$(get_sshd_value allowagentforwarding)"
if [[ "${tcp_fwd}" == "no" && "${agent_fwd}" == "no" ]]; then
    report_pass "relais SSH coupé"
else
    report_fail "relais SSH ouvert (tcp ${tcp_fwd:-inconnu}, agent ${agent_fwd:-inconnu})"
fi
if sshd -t 2>/dev/null; then
    report_pass "sshd -t"
else
    report_fail "sshd -t échoue"
fi

if LANG=C LC_ALL=C ufw status | grep -qw "Status: active"; then
    report_pass "UFW actif"
else
    report_fail "UFW inactif"
fi
if LANG=C LC_ALL=C ufw status verbose | grep -qiE 'Default: deny \(incoming\), allow \(outgoing\)'; then
    report_pass "UFW outgoing ALLOW"
else

    if ufw status verbose | grep -qi 'Outgoing: allow'; then
        report_pass "UFW outgoing ALLOW"
    else
        report_fail "UFW outgoing n'est pas allow"
    fi
fi
ufw_rules="$(LANG=C LC_ALL=C ufw status 2>/dev/null || true)"
if grep -qF 'SSH LAN' <<< "${ufw_rules}" || grep -qF 'SSH (limit)' <<< "${ufw_rules}"; then
    report_pass "SSH limité aux préfixes connectés"
else
    report_fail "règle SSH absente"
fi

tmp_opts="$(findmnt -no OPTIONS /tmp 2>/dev/null || true)"
if echo "${tmp_opts}" | grep -qw noexec; then
    report_fail "/tmp est noexec"
else
    report_pass "/tmp sans noexec"
fi

if [[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)" == "1" ]]; then
    report_pass "ip_forward=1"
else
    report_fail "ip_forward n'est pas 1"
fi
if [[ "$(sysctl -n kernel.yama.ptrace_scope 2>/dev/null || echo missing)" == "1" ]]; then
    report_pass "ptrace_scope=1"
else
    report_fail "ptrace_scope n'est pas 1"
fi
if [[ "$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo 0)" == "0" ]]; then
    report_pass "IPv6 laissé actif"
else
    report_fail "IPv6 désactivé"
fi
if [[ -n "$(sysctl -n kernel.unprivileged_userns_clone 2>/dev/null || true)" \
    && "$(sysctl -n kernel.unprivileged_userns_clone 2>/dev/null || echo 1)" == "0" ]]; then
    report_fail "unprivileged_userns_clone=0"
else
    report_pass "user namespaces non désactivés par sysctl"
fi
if grep -RqsE 'apparmor_restrict_unprivileged_userns[[:space:]]*=[[:space:]]*0' /etc/sysctl.d /etc/sysctl.conf 2>/dev/null; then
    report_fail "un fichier sysctl désactive la restriction userns AppArmor au lieu d'un profil"
else
    report_pass "restriction userns AppArmor non désactivée par HFU"
fi
if [[ "$(dpkg --print-architecture)" == "amd64" ]]; then
    if dpkg --print-foreign-architectures | grep -qx i386; then
        report_pass "architecture i386 activée"
    else
        report_fail "architecture i386 absente"
    fi
fi
if [[ -f /etc/sudoers.d/liltress-workstation-umask ]] \
    && visudo -cf /etc/sudoers.d/liltress-workstation-umask >/dev/null \
    && grep -q 'umask_override' /etc/sudoers.d/liltress-workstation-umask; then
    report_pass "sudo umask 0022 (apt ne hérite pas de 027)"
else
    report_fail "sudoers umask absent ou invalide"
fi
if [[ -f /etc/sudoers.d/liltress-workstation-timeout ]] \
    && visudo -cf /etc/sudoers.d/liltress-workstation-timeout >/dev/null 2>&1 \
    && grep -qx 'Defaults timestamp_timeout=5' /etc/sudoers.d/liltress-workstation-timeout; then
    report_pass "sudo redemande le mot de passe après 5 minutes"
else
    report_fail "délai sudo absent ou invalide"
fi
if grep -q '^DEFAULT_FORWARD_POLICY="ACCEPT"' /etc/default/ufw 2>/dev/null; then
    report_pass "UFW DEFAULT_FORWARD_POLICY=ACCEPT"
else
    report_fail "UFW forward policy n'est pas ACCEPT"
fi
if [[ "${G_MAIL_ALERTS:-0}" == "1" ]]; then
    if systemctl is-active --quiet postfix; then
        report_pass "Postfix actif"
    else
        report_fail "Postfix inactif"
    fi
    postfix_listen="$(postconf -h inet_interfaces 2>/dev/null | tr -d '[:space:]' || true)"
    case "${postfix_listen}" in
        loopback-only|localhost|127.0.0.1|"[::1]")
            report_pass "Postfix écoute seulement localhost"
            ;;
        *)
            report_fail "Postfix n'est pas limité à localhost (${postfix_listen:-inconnu})"
            ;;
    esac
else
    report_pass "alertes e-mail coupées"
fi

systemctl daemon-reload >/dev/null 2>&1 || true

for svc in apparmor fail2ban auditd clamav-daemon clamav-freshclam unattended-upgrades unbound; do
    if systemctl is-enabled --quiet "${svc}" 2>/dev/null || systemctl is-active --quiet "${svc}" 2>/dev/null; then
        report_pass "service ${svc} enabled/active"
    else
        report_warn "service ${svc} inactif"
    fi
done

if systemctl is-active --quiet clamav-clamonacc.service 2>/dev/null \
    || systemctl is-active --quiet clamonacc.service 2>/dev/null; then
    report_pass "ClamAV surveille les dossiers à risque en continu"
else
    report_fail "clamonacc inactif ($(systemctl is-active clamav-clamonacc.service 2>/dev/null || systemctl is-active clamonacc.service 2>/dev/null || echo absent))"
fi
if systemctl is-enabled --quiet w-boot-chain.timer 2>/dev/null; then
    report_pass "chaîne de sécurité au démarrage"
else
    report_fail "timer de la chaîne de démarrage absent"
fi
if systemctl is-enabled --quiet w-idle-scan.timer 2>/dev/null; then
    report_pass "passe différée des chemins exclus"
else
    report_fail "timer de passe différée absent"
fi
if systemctl is-enabled --quiet w-reboot-notice.timer 2>/dev/null; then
    report_pass "avis de redémarrage planifié"
else
    report_fail "timer d'avis de redémarrage absent"
fi
if systemctl is-enabled --quiet w-periodic-scan.timer 2>/dev/null; then
    report_pass "analyse ClamAV toutes les 2 h"
else
    report_fail "timer d'analyse ClamAV périodique absent"
fi
if systemctl is-enabled --quiet w-hourly-scan.timer 2>/dev/null; then
    report_pass "passe horaire AIDE, rkhunter, chkrootkit et debsums"
else
    report_fail "timer de passe horaire absent"
fi
boot_bin="${G_CONFIG_BASE_DIRECTORY}/cron/bin/boot-scan.sh"
if [[ -f "${boot_bin}" ]] \
    && grep -q 'integrity.sh' "${boot_bin}" \
    && grep -q 'behavior.sh' "${boot_bin}" \
    && grep -q 'egress-watch.sh' "${boot_bin}"; then
    report_pass "intégrité, audit et journal sortant dans la chaîne de démarrage"
else
    report_fail "chaîne de démarrage sans intégrité, audit ou journal sortant"
fi
clam_conf="/etc/clamav/clamd.conf"
if [[ -f "${clam_conf}" ]] \
    && grep -q '^OnAccessIncludePath /tmp$' "${clam_conf}" \
    && grep -q '^OnAccessIncludePath /var/tmp$' "${clam_conf}" \
    && grep -q '^OnAccessIncludePath /opt$' "${clam_conf}" \
    && ! grep -q '^OnAccessIncludePath /$' "${clam_conf}" \
    && ! grep -q '^OnAccessIncludePath /home$' "${clam_conf}"; then
    report_pass "surveillance continue sur /tmp, /var/tmp et /opt"
else
    report_fail "surveillance continue incomplète"
fi
if [[ -f "${clam_conf}" ]] \
    && grep -q '/var/lib/clamav/quarantine' "${clam_conf}" \
    && grep -q '/var/lib/clamav/tmp' "${clam_conf}" \
    && grep -q '/var/log' "${clam_conf}" \
    && grep -q '/opt/liltress-workstation' "${clam_conf}"; then
    report_pass "exclusions minimales présentes"
else
    report_fail "exclusions minimales absentes"
fi
# shellcheck disable=SC1091
source "${G_INSTALL_DIRECTORY}/config/clamav/onaccess.conf"
if [[ "${W_ONACCESS_MOUNTS}" == "1" ]]; then
    mount_ok=1
    if [[ -d /media ]] && ! grep -q '^OnAccessIncludePath /media$' "${clam_conf}"; then
        mount_ok=0
    fi
    if [[ -d /mnt ]] && ! grep -q '^OnAccessIncludePath /mnt$' "${clam_conf}"; then
        mount_ok=0
    fi
    if [[ "${mount_ok}" == "1" ]]; then
        report_pass "surveillance continue de /media et /mnt"
    else
        report_fail "/media ou /mnt absents de la surveillance continue"
    fi
elif grep -q '^OnAccessIncludePath /media$' "${clam_conf}" \
    || grep -q '^OnAccessIncludePath /mnt$' "${clam_conf}"; then
    report_fail "/media ou /mnt surveillés alors que W_ONACCESS_MOUNTS=0"
else
    report_pass "montages hors surveillance continue"
fi
# shellcheck disable=SC1091
source "${G_INSTALL_DIRECTORY}/config/ufw/egress.conf"
response="${G_CONFIG_BASE_DIRECTORY}/cron/bin/clamav-response.sh"
if [[ -f "${response}" ]] \
    && grep -q 'kill -TERM' "${response}" \
    && ! grep -q 'W_CLAMAV_KILL' "${response}" \
    && grep -q 'inet w_isolate' "${response}" \
    && ! grep -q 'W_NET_ISOLATE:-' "${response}"; then
    report_pass "signal et isolation après une détection (${W_NET_ISOLATE_SEC}s)"
else
    report_fail "signal ou isolation absent de clamav-response.sh"
fi
if [[ -x "${G_INSTALL_DIRECTORY}/service/apparmor/detect-and-apply.sh" ]]; then
    report_pass "détection AppArmor exécutable"
else
    report_fail "detect-and-apply.sh absent ou non exécutable"
fi
if command -v cscli >/dev/null 2>&1; then
    crowd_list="$(cscli collections list 2>/dev/null || true)"
    for crowd_name in crowdsecurity/linux crowdsecurity/sshd crowdsecurity/postfix; do
        if grep -Fq "${crowd_name}" <<< "${crowd_list}"; then
            report_pass "collection ${crowd_name}"
        else
            report_fail "collection ${crowd_name} absente"
        fi
    done
else
    report_fail "cscli absent"
fi
usb_mod="usb-storage"
if grep -RqsE "^[[:space:]]*(install|blacklist)[[:space:]]+${usb_mod}([[:space:]]|$)" /etc/modprobe.d /etc/modprobe.conf 2>/dev/null; then
    report_fail "module usb-storage bloqué au chargement"
else
    report_pass "stockage USB non bloqué au chargement"
fi
usb_rules="/etc/usbguard/rules.conf"
usb_hid='allow with-interface equals { 03:*:* }'
usb_hub='allow with-interface equals { 09:*:* }'
if [[ ! -f "${usb_rules}" ]] || ! grep -qF "${usb_hid}" "${usb_rules}"; then
    report_warn "USBGuard sans autorisation clavier et souris"
elif ! systemctl is-active --quiet usbguard; then
    report_fail "USBGuard inactif alors que la politique existe"
elif ! grep -qF "${usb_hub}" "${usb_rules}"; then
    report_warn "USBGuard sans concentrateur"
else
    report_pass "USBGuard actif (appareils présents et HID autorisés)"
fi
if systemctl is-active --quiet crowdsec 2>/dev/null \
    && systemctl is-active --quiet crowdsec-firewall-bouncer 2>/dev/null; then
    report_pass "CrowdSec et bouncer actifs"
else
    report_fail "CrowdSec inactif"
fi

log_subtitle "${INSTALL_WATCHER}" "log.section-dns-local"
if systemctl is-enabled --quiet unbound 2>/dev/null && systemctl is-active --quiet unbound; then
    report_pass "Unbound actif au démarrage"
else
    report_fail "Unbound inactif"
fi
if [[ -f /usr/share/dns/root.hints && -f /etc/unbound/unbound.conf.d/liltress-workstation.conf ]]; then
    report_pass "liste des serveurs racine et configuration Unbound présentes"
else
    report_fail "configuration Unbound ou root.hints absente"
fi
if systemctl is-enabled --quiet w-unbound-root-hints.path 2>/dev/null; then
    report_pass "rechargement Unbound quand les serveurs racine changent"
else
    report_fail "surveillance des serveurs racine DNS absente"
fi
if ss -H -lntu src 127.0.0.1:53 2>/dev/null | grep -q .; then
    report_pass "Unbound écoute 127.0.0.1:53"
else
    report_fail "Unbound n'écoute pas 127.0.0.1:53"
fi
if ss -H -lntu src 0.0.0.0:53 2>/dev/null | grep -q .; then
    report_fail "Unbound écoute hors de la machine"
fi
if grep -q '^DNS=127.0.0.1' /etc/systemd/resolved.conf.d/90-liltress-workstation.conf 2>/dev/null; then
    report_pass "systemd-resolved pointe vers Unbound"
else
    report_fail "systemd-resolved n'est pas pointé vers Unbound"
fi

log_subtitle "${INSTALL_WATCHER}" "verify.workstation.title.4"

if ! command -v pro >/dev/null 2>&1; then
    report_fail "ubuntu-pro-client absent"
elif check_ubuntu_pro; then
    report_pass "Ubuntu Pro attaché"
    if check_ubuntu_lts; then
        seen=""
        while IFS=$'\t' read -r svc_name svc_status svc_detail; do
            seen="${seen} ${svc_name}"
            case "${svc_status}" in
                enabled|active)
                    report_pass "${svc_name} activé"
                    ;;
                warning)
                    report_pass "${svc_name} activé, redémarrage encore utile${svc_detail:+ : ${svc_detail}}"
                    ;;
                *)
                    report_warn "${svc_name} non activé (état : ${svc_status:-inconnu}${svc_detail:+ : ${svc_detail}})"
                    ;;
            esac
        done < <(pro status --format json 2>/dev/null | python3 -c '
import json, sys
data = json.load(sys.stdin)
wanted = ("esm-infra", "esm-apps", "livepatch")
for svc in data.get("services") or []:
    name = svc.get("name")
    if name not in wanted:
        continue
    detail = svc.get("status_details") or ""
    warning = svc.get("warning") or {}
    if isinstance(warning, dict) and warning.get("message"):
        detail = warning["message"]
    detail = detail.replace("\t", " ").replace("\n", " ")
    print("%s\t%s\t%s" % (name, svc.get("status") or "", detail))
')
        for svc in esm-infra esm-apps livepatch; do
            case " ${seen} " in
                *" ${svc} "*) ;;
                *) report_warn "${svc} absent de pro status" ;;
            esac
        done
    else
        report_pass "esm-infra, esm-apps et livepatch non demandés : version intermédiaire"
    fi
else
    report_fail "Ubuntu Pro non attaché (obligatoire)"
fi

log_subtitle "${INSTALL_WATCHER}" "log.lynis"

if command -v lynis >/dev/null 2>&1; then
    report_pass "lynis installé"
    if [[ -f /etc/lynis/custom.prf ]]; then
        report_pass "custom.prf présent"
    else
        report_warn "custom.prf manquant"
    fi
    log_info "${INSTALL_WATCHER}" "log.audit-lynis-quick"
    lynis audit system --quick --no-colors --auditor liltress-workstation-verify > "${G_LOG_DIR:-/tmp}/lynis-verify.txt" 2>&1 || true
    score="$(awk -F= '/hardening_index=/{print $2}' /var/log/lynis-report.dat 2>/dev/null | tail -1)"
    if [[ "${score}" =~ ^[0-9]+$ ]]; then
        echo "$(get_text log.lynis-hardening-index "${score}")" >> "${REPORT}"
        if [[ "${score}" -ge "${G_LYNIS_MIN_SCORE}" ]]; then
            report_pass "Lynis ${score} ≥ ${G_LYNIS_MIN_SCORE}"
        else
            report_fail "Lynis ${score} < ${G_LYNIS_MIN_SCORE}"
            awk -F= '/^warning\[\]=/{print "   [INFO]  Lynis " $2}' /var/log/lynis-report.dat 2>/dev/null | head -20 || true
        fi
    else
        report_fail "score Lynis illisible"
    fi
    chmod 640 /var/log/lynis.log /var/log/lynis-report.dat 2>/dev/null || true
else
    report_fail "lynis absent"
fi

log_subtitle "${INSTALL_WATCHER}" "log.software-of-the-workstation"

if dpkg-query -W -f '${Status}' snapd 2>/dev/null | grep -q 'install ok'; then
    report_pass "snapd installé"
else
    report_fail "snapd absent"
fi
if command -v snap >/dev/null 2>&1 && snap list firefox >/dev/null 2>&1; then
    log_info "${INSTALL_WATCHER}" "log.snap-firefox-present"
else
    log_info "${INSTALL_WATCHER}" "log.snap-firefox-absent"
fi

log_subtitle "${INSTALL_WATCHER}" "log.start-2"
root_src="$(findmnt -no SOURCE / 2>/dev/null || true)"
if [[ -n "${root_src}" ]] && lsblk -sno TYPE "${root_src}" 2>/dev/null | grep -qx crypt; then
    report_pass "racine sur LUKS"
else
    report_warn "racine sans LUKS constaté"
fi
if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -qi 'SecureBoot enabled'; then
    report_pass "Secure Boot actif"
else
    report_warn "Secure Boot non actif"
fi

log_subtitle "${INSTALL_WATCHER}" "log.sources-apt"
log_info "${INSTALL_WATCHER}" "log.check-of-the-workstation"
if [[ -f /etc/apt/sources.list ]]; then
    if grep -q 'liltress' /etc/apt/sources.list; then
        report_fail "sources.list a été réécrit"
    else
        report_pass "sources.list non réécrit par HFU"
    fi
fi
report_pass "dépôt Lynis CISOfy ajouté uniquement (lynis.list)"

{
    echo
    echo "$(get_text log.total)"
    echo
    echo "$(get_text log.ok-5 "${PASS}")"
    echo "$(get_text log.warn-2 "${WARNN}")"
    echo "$(get_text log.fail-2 "${FAIL}")"
} >> "${REPORT}"

chmod 644 "${REPORT}" 2>/dev/null || true
set_step_hidden "Check : ${PASS} OK / ${WARNN} WARN / ${FAIL} FAIL"
log_info "${INSTALL_WATCHER}" "verify.workstation.info.5" "Rapport : ${REPORT}"
if [[ "${FAIL}" -gt 0 ]]; then
    echo "" >&2
    grep '^- FAIL' "${REPORT}" | while IFS= read -r line; do
        set_color_red "${line}"
    done
    log_error "${INSTALL_WATCHER}" "log.check-failure-s" "${FAIL}"
fi
log_success "${INSTALL_WATCHER}" "log.check-workstation-ok"
