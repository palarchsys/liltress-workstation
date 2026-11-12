#!/usr/bin/env bash
# =============================================================================
# File       : script/test/suites/02_file_graph.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================


locate_python_dir() {
    local dir hops=0 candidate
    for candidate in \
        "${CONFIG_BASE_DIRECTORY:-}/python" \
        "${BASE:-}/python" \
        "${INSTALL_DIRECTORY:-}/python" \
        "${INSTALL_DIRECTORY:-}/../share/python"
    do
        if [[ -n "${candidate}" && -d "${candidate}" ]]; then
            (cd -- "${candidate}" && pwd -P)
            return 0
        fi
    done
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        if [[ -d "${dir}/share/python" ]]; then
            printf '%s\n' "${dir}/share/python"
            return 0
        fi
        if [[ -d "${dir}/python" ]]; then
            (cd -- "${dir}/python" && pwd -P)
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

t_get_plan_pos() {
    python3 "$(locate_python_dir)/install-plan.py" index "${T_ROOT}/config/schema/installation.json" "$1"
}

t_section "étapes de run.sh"
while IFS= read -r step; do
    [[ -z "${step}" ]] && continue
    if [[ -f "${T_ROOT}/${step}" ]]; then
        t_pass "graph:${step}" "présent"
    else
        t_fail "graph:${step}" "introuvable"
    fi
done < <(python3 "$(locate_python_dir)/install-plan.py" paths "${T_ROOT}/config/schema/installation.json"
)

t_section "désinstallations avant system/install"
snap_line=$(t_get_plan_pos 'system/purge/snapd.sh')
cups_line=$(t_get_plan_pos 'install.purge.cups')
inst_line=$(t_get_plan_pos 'script/project-tree.sh')
removed_line=$(t_get_plan_pos 'install.purge.removed')
locks_line=$(t_get_plan_pos 'install.purge.locks')
if [[ -n "${snap_line}" && -n "${cups_line}" && -n "${inst_line}" \
      && "${snap_line}" -lt "${cups_line}" && "${cups_line}" -lt "${inst_line}" ]] \
   && [[ "$(t_get_plan_pos 'install.purge.cups')" -lt "$(t_get_plan_pos 'install.purge.rc')" ]] \
   && [[ "$(t_get_plan_pos 'install.purge.rc')" -lt "$(t_get_plan_pos 'install.purge.mask')" ]] \
   && grep -q 'systemctl mask systemd-coredump.socket' "${T_ROOT}/system/purge/coredump.sh" \
   && ! grep -q 'systemctl mask systemd-coredump.socket' "${T_ROOT}/system/kernel/configure.sh" \
   && ! grep -q 'mask apport' "${T_ROOT}/system/purge/coredump.sh" \
   && grep -q 'cups cups-daemon cups-browsed cups-core-drivers cups-server-common cups-filters' "${T_ROOT}/system/purge/cups.sh" \
   && grep -qF 'run_silent_apt' "${T_ROOT}/system/purge/cups.sh" \
   && [[ "$(t_get_plan_pos 'apt-upgrade')" -lt "${removed_line}" ]] \
   && [[ "${removed_line}" -lt "${locks_line}" ]]; then
    t_pass "graph.order.purge-first" "snap (L${snap_line}), CUPS (L${cups_line}), arbre (L${inst_line})"
else
    t_fail "graph.order.purge-first" "snap, puis purge de CUPS et des paquets rc, avant l'arbre"
fi

t_section "purge rc avant les bases rkhunter et AIDE"
rc_line=$(t_get_plan_pos 'install.purge.removed')
rk_line=$(t_get_plan_pos 'service/rkhunter/init-db.sh')
aide_line=$(t_get_plan_pos 'service/aide/init-db.sh')
if [[ -n "${rc_line}" && -n "${rk_line}" && -n "${aide_line}" \
      && "${rc_line}" -lt "${rk_line}" && "${rk_line}" -lt "${aide_line}" ]] \
   && ! grep -q 'dpkg --purge' "${T_ROOT}/system/base/install.sh" \
   && ! grep -qF 'rkhunter --propupd' "${T_ROOT}/service/rkhunter/configure.sh" \
   && grep -qF 'rkhunter --propupd' "${T_ROOT}/service/rkhunter/init-db.sh"; then
    t_pass "graph.order.purge-before-db" "purge rc (L${rc_line}) avant rkhunter (L${rk_line}) et AIDE (L${aide_line})"
else
    t_fail "graph.order.purge-before-db" "la purge rc doit précéder --propupd et aide --init"
fi

t_section "carte sasl selon postfix"
if grep -q 'get_sasl_map_type' "${T_ROOT}/service/postfix/configure.sh" \
   && grep -q 'sasl_passwd.db' "${T_ROOT}/service/postfix/configure.sh" \
   && grep -q 'sasl_passwd.cdb' "${T_ROOT}/service/postfix/configure.sh" \
   && grep -q '__SASL_TYPE__' "${T_ROOT}/core/mail/mail.sh" \
   && grep -q '__SASL_TYPE__:/etc/postfix/sasl_passwd' "${T_ROOT}/config/postfix/main.keys" \
   && ! grep -q 'hash:/etc/postfix/sasl_passwd' "${T_ROOT}/config/postfix/main.keys" \
   && ! grep -q 'cdb:/etc/postfix/sasl_passwd' "${T_ROOT}/config/postfix/main.keys"; then
    t_pass "graph.postfix.cdb" "carte SASL selon default_database_type"
else
    t_fail "graph.postfix.cdb" "la carte SASL est figée sur un seul type"
fi

t_section "ubuntu pro hors lts"
if awk '
    /if check_ubuntu_lts; then/ { state = 1; next }
    state == 1 && /^else$/ { state = 2; next }
    state == 2 && /^fi$/ { state = 0; closed = 1; next }
    state == 1 && /pro enable/ { inn++ }
    state == 1 && /esm-infra esm-apps/ { names = 1 }
    state == 1 && /pro enable livepatch/ { live = 1 }
    state == 2 && /pro enable/ { bad = 1 }
    END { exit !(inn == 2 && names && live && !bad && closed) }
' "${T_ROOT}/service/ubuntu-pro/install.sh" \
   && grep -q 'check_ubuntu_lts' "${T_ROOT}/script/verify/workstation.sh" \
   && grep -qF 'non demandés : version intermédiaire' "${T_ROOT}/script/verify/workstation.sh"; then
    t_pass "graph.pro.interim" "esm-infra, esm-apps et livepatch seulement sur une LTS"
else
    t_fail "graph.pro.interim" "le poste active encore esm ou livepatch hors LTS"
fi

t_section "ordre des contrôles quotidiens"
if [[ "$(t_get_plan_pos 'service/ssh/configure.sh')" -lt "$(t_get_plan_pos 'service/ufw/configure.sh')" ]] \
   && [[ "$(t_get_plan_pos 'service/usbguard/install.sh')" -lt "$(t_get_plan_pos 'service/usbguard/configure.sh')" ]] \
   && [[ "$(t_get_plan_pos 'service/clamav/install.sh')" -lt "$(t_get_plan_pos 'service/clamav/configure.sh')" ]] \
   && [[ "$(t_get_plan_pos 'service/clamav/configure.sh')" -lt "$(t_get_plan_pos 'service/apparmor/userns.sh')" ]] \
   && [[ "$(t_get_plan_pos 'service/apparmor/userns.sh')" -lt "$(t_get_plan_pos 'apt-upgrade')" ]] \
   && [[ "$(t_get_plan_pos 'apt-upgrade')" -lt "$(t_get_plan_pos 'service/usbguard/configure.sh')" ]] \
   && [[ "$(t_get_plan_pos 'service/usbguard/configure.sh')" -lt "$(t_get_plan_pos 'service/rkhunter/init-db.sh')" ]] \
   && [[ "$(t_get_plan_pos 'service/rkhunter/init-db.sh')" -lt "$(t_get_plan_pos 'service/aide/init-db.sh')" ]] \
   && [[ "$(t_get_plan_pos 'service/aide/init-db.sh')" -lt "$(t_get_plan_pos 'script/verify/workstation.sh')" ]]; then
    t_pass "graph.order.daily" "SSH avant UFW, USBGuard après correctifs, verify après AIDE"
else
    t_fail "graph.order.daily" "USBGuard suit les paquets ; verify suit AIDE"
fi

t_section "modèle de mail dans template/"
if [[ -f "${T_ROOT}/template/mail.html" ]]; then
    t_pass "graph.template:mail.html" "présent : template/mail.html"
else
    t_fail "graph.template:mail.html" "fichier introuvable : template/mail.html"
fi
if [[ -e "${T_ROOT}/service/cron/watchdogs/mail.html" ]]; then
    t_fail "graph.template:not-in-watchdogs" "mail.html est encore dans service/cron/watchdogs"
else
    t_pass "graph.template:not-in-watchdogs" "le modèle n'est pas enfoui dans les watchdogs"
fi

t_section "debsums et mirrors.dat"
rk="${T_ROOT}/service/cron/watchdogs/rkhunter.sh"
check_line="$(grep -n 'record-mirrors.sh" check' "${rk}" | head -1 | cut -d: -f1)"
update_line="$(grep -n 'rkhunter --update' "${rk}" | head -1 | cut -d: -f1)"
save_line="$(grep -n 'record-mirrors.sh" save' "${rk}" | head -1 | cut -d: -f1)"
if [[ -x "${T_ROOT}/service/cron/watchdogs/record-mirrors.sh" ]] \
   && [[ -n "${check_line}" && -n "${update_line}" && -n "${save_line}" ]] \
   && [[ "${check_line}" -lt "${update_line}" && "${update_line}" -lt "${save_line}" ]] \
   && grep -q 'rkhunter-mirrors.sha256' "${T_ROOT}/../share/python/debsums-filter.py" \
   && grep -q 'perl-base/unicore' "${T_ROOT}/../share/python/debsums-filter.py" \
   && grep -q 'record-mirrors.sh" save' "${T_ROOT}/service/rkhunter/init-db.sh" \
   && [[ ! -e "${T_ROOT}/service/cron/watchdogs/debsums.ignore" ]]; then
    t_pass "graph.debsums.mirrors" "empreinte après --update, le fichier n'est pas ignoré"
else
    t_fail "graph.debsums.mirrors" "mirrors.dat doit rester contrôlé hors de rkhunter --update"
fi

t_section "clamav verrous de quarantaine"
evt="${T_ROOT}/service/cron/watchdogs/clamav-event.sh"
if grep -q 'clamav-quarantine-lock' "${evt}" \
   && awk '
        /clamav-quarantine-lock/ { lock = NR }
        /log_alert/ { if (lock && !alert) alert = NR }
        END { exit !(lock && alert && alert > lock) }
      ' "${evt}"; then
    t_pass "graph.clamav.locks" "un verrou de quarantaine sort avant le courrier"
else
    t_fail "graph.clamav.locks" "les verrous .clamav-quarantine-lock.* ne doivent pas envoyer de courrier"
fi

t_section "chemins exclus du scan"
skip_lib="${T_ROOT}/service/cron/watchdogs/scan-skip-lib.sh"
skip_tpl="${T_ROOT}/config/clamav/scan-skip.paths"
skip_apply="${T_ROOT}/service/cron/watchdogs/apply-scan-skip.sh"
skip_cmd="${T_ROOT}/script/scan-skip.sh"
skip_idle="${T_ROOT}/service/cron/watchdogs/idle-scan.sh"
skip_boot="${T_ROOT}/service/cron/watchdogs/boot-scan.sh"
skip_clam="${T_ROOT}/service/cron/watchdogs/clamav.sh"
if [[ -f "${skip_lib}" && -f "${skip_tpl}" && -f "${skip_apply}" && -f "${skip_cmd}" && -f "${skip_idle}" ]] \
   && grep -q '/var/jeux' "${skip_tpl}" \
   && grep -q '__HOME__/.cache' "${skip_tpl}" \
   && grep -q '__HOME__/snap' "${skip_tpl}" \
   && grep -q '__HOME__' "${skip_tpl}" \
   && grep -qF "printf '%s\\n' / /home /opt /tmp /etc /usr /var /boot /root" "${skip_lib}" \
   && grep -q '# home=' "${skip_tpl}" \
   && grep -qF '/var/jeux/*' "${skip_lib}" \
   && grep -q 'BEGIN Liltress Workstation scan-skip' "${T_ROOT}/../share/python/scan-skip-apply.py" \
   && grep -q 'OnAccessExcludePath' "${skip_apply}" \
   && grep -q 'systemctl restart clamav-daemon' "${skip_apply}" \
   && grep -q 'clamav-clamonacc.service' "${skip_apply}" \
   && ! grep -q 'systemctl reload' "${skip_apply}" \
   && grep -q 'SCAN_SKIP_HOME' "${T_ROOT}/service/clamav/configure.sh" \
   && grep -q 'SCAN_SKIP_HOME' "${T_ROOT}/service/cron/configure.sh" \
   && awk '
        /chain\.sh/ { if (!chain) chain = NR }
        /apply-scan-skip\.sh/ { if (chain && !apply) apply = NR }
        END { exit !(chain && apply && apply > chain) }
      ' "${skip_boot}" \
   && ! grep -q 'clamdscan' "${skip_clam}" \
   && grep -q 'list_clamav_scan' "${skip_clam}" \
   && grep -q 'report_clamav' "${skip_clam}" \
   && grep -q 'clamscan --infected --no-summary' "${T_ROOT}/../share/core/watchdog/clamav.sh" \
   && grep -q 'planté signal' "${T_ROOT}/../share/core/watchdog/clamav.sh" \
   && grep -q 'tool="clamscan"' "${T_ROOT}/../share/core/watchdog/clamav.sh" \
   && grep -q 'scan-skip.sh list' "${T_ROOT}/../share/locale/fr/log.txt" \
   && grep -q 'log.usage-sudo-bash-bin-scan-skip-sh-list' "${skip_cmd}" \
   && grep -q 'scan-skip.sh add' "${T_ROOT}/../share/locale/fr/log.txt" \
   && grep -q 'log.sudo-bash-bin-scan-skip-sh-add-chemin' "${skip_cmd}" \
   && grep -q 'scan-skip.sh del' "${T_ROOT}/../share/locale/fr/log.txt" \
   && grep -q 'log.sudo-bash-bin-scan-skip-sh-del-chemin' "${skip_cmd}" \
   && grep -q 'pgrep -x' "${skip_idle}" \
   && grep -q 'list_clamav_scan' "${skip_idle}" \
   && grep -q 'report_clamav' "${skip_idle}" \
   && ! grep -q 'interrompu, aucun virus' "${skip_clam}" \
   && ! grep -q 'interrompu, aucun virus' "${skip_idle}" \
   && grep -q 'get_crash_sentence' "${skip_boot}" \
   && grep -q 'get_crash_sentence' "${T_ROOT}/service/cron/watchdogs/aide.sh" \
   && grep -q 'get_crash_sentence' "${T_ROOT}/service/cron/watchdogs/rkhunter.sh" \
   && grep -q 'get_crash_sentence' "${T_ROOT}/service/cron/watchdogs/chkrootkit.sh" \
   && grep -q 'get_crash_sentence' "${T_ROOT}/service/cron/watchdogs/debsums.sh" \
   && grep -q 'clamscan : infection(s)' "${T_ROOT}/../share/locale/fr/watchdog.txt" \
   && grep -q 'AIDE: changements détectés' "${T_ROOT}/../share/locale/fr/watchdog.txt" \
   && grep -q 'rkhunter warnings' "${T_ROOT}/../share/locale/fr/watchdog.txt" \
   && grep -q 'chkrootkit a produit une sortie' "${T_ROOT}/../share/locale/fr/watchdog.txt" \
   && grep -q 'reset_debsums_log' "${T_ROOT}/service/cron/watchdogs/debsums.sh" \
   && grep -q '"apt-get", "clean"' "${T_ROOT}/../share/python/debsums-reset.py" \
   && grep -q 'Dir::Cache::archives' "${T_ROOT}/../share/python/debsums-reset.py" \
   && grep -q '"install", "--reinstall", "-y", "--", pkg' "${T_ROOT}/../share/python/debsums-reset.py" \
   && grep -q '/var/cache/apt/archives' "${T_ROOT}/../share/python/debsums-reset.py" \
   && grep -q 'RKHUNTER_REFRESH=1' "${T_ROOT}/service/cron/watchdogs/rkhunter.sh" \
   && grep -q 'rkhunter-refresh-db.sh' "${T_ROOT}/../share/core/watchdog/remedy.sh" \
   && grep -q 'rkhunter-refresh-db.sh' "${T_ROOT}/service/rkhunter/configure.sh" \
   && grep -q 'get_text watchdog.clamav-in' "${T_ROOT}/service/cron/watchdogs/clamav-event.sh" \
   && grep -q 'ClamAV :' "${T_ROOT}/../share/locale/fr/watchdog.txt" \
   && grep -q 'get_clamav_kind' "${skip_clam}" \
   && grep -q 'get_clamav_kind' "${skip_idle}" \
   && grep -q 'ALLOWDEVFILE=/dev/log' "${T_ROOT}/config/rkhunter/rkhunter.conf.local" \
   && grep -qF "'/dev/log'" "${T_ROOT}/service/cron/watchdogs/rkhunter.sh" \
   && grep -q 'w-idle-scan.timer' "${T_ROOT}/service/cron/configure.sh" \
   && grep -q 'Liltress Workstation onaccess' "${T_ROOT}/config/clamav/onaccess.conf" \
   && ! grep -q 'OnAccessExcludePath' "${T_ROOT}/service/clamav/configure.sh"; then
    t_pass "graph.scan-skip" "fichier de chemins, commande et passe différée"
else
    t_fail "graph.scan-skip" "les exclusions passent par scan-skip.paths"
fi

t_section "ordre Unbound et liste chkrootkit"
order_ok=1
if grep -q 'systemd-resolved' "${T_ROOT}/config/unbound/service.conf"; then
    order_ok=0
fi
if grep -q '^After=unbound' "${T_ROOT}/config/unbound/resolved-service.conf"; then
    order_ok=0
fi
grep -q '^Wants=unbound.service$' "${T_ROOT}/config/unbound/resolved-service.conf" || order_ok=0
grep -q 'chkrootkit/patterns.ignore' "${T_ROOT}/service/chkrootkit/install.sh" || order_ok=0
grep -q 'src/config/chkrootkit' "${T_ROOT}/service/chkrootkit/install.sh" || order_ok=0
if [[ "${order_ok}" -eq 1 ]]; then
    t_pass "graph.unbound.order" "Unbound après le réseau, liste chkrootkit installée"
else
    t_fail "graph.unbound.order" "Unbound ne doit pas précéder systemd-resolved, la liste chkrootkit doit être copiée"
fi

t_section "plafond CPU"
cpu_rc=0
bash -s -- "${T_ROOT}" << 'CPU' || cpu_rc=$?
set -euo pipefail
root="$1"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
printf '%s\n' '#!/bin/sh' 'echo 4' > "${work}/nproc"
chmod 755 "${work}/nproc"
got="$(PATH="${work}:${PATH}" WATCHDOG_CPU_LIMIT=20 bash -c 'source "$1" && get_cpu_quota_percent' _ "${root}/../share/core/watchdog/watchdog.sh")"
[[ "${got}" == "80" ]]
grep -qF 'get_cpu_quota_percent' "${root}/service/cron/configure.sh"
grep -qF 'CPUQuota=${cpu_quota}%' "${root}/config/cron/w-boot-scan.service"
grep -qF 'CPUQuota=${cpu_quota}%' "${root}/config/cron/w-idle-scan.service"
grep -qF 'CPUQuota=${cpu_quota}%' "${root}/config/cron/w-reboot-notice.service"
grep -qF 'CPUQuota=${cpu_quota}%' "${root}/config/cron/w-periodic-scan.service"
grep -qF 'CPUQuota=${cpu_quota}%' "${root}/config/cron/w-hourly-scan.service"
! grep -qF 'CPUQuota=${WATCHDOG_CPU_LIMIT}%' \
    "${root}/service/cron/configure.sh" \
    "${root}/config/cron/w-boot-scan.service" \
    "${root}/config/cron/w-idle-scan.service" \
    "${root}/config/cron/w-reboot-notice.service" \
    "${root}/config/cron/w-boot-chain.service" \
    "${root}/config/cron/w-periodic-scan.service" \
    "${root}/config/cron/w-hourly-scan.service"
CPU
if [[ "${cpu_rc}" -eq 0 ]]; then
    t_pass "graph.cpu.quota" "20 % de la machine, CPUQuota multiplié par le nombre de CPU"
else
    t_fail "graph.cpu.quota" "CPUQuota doit valoir WATCHDOG_CPU_LIMIT fois le nombre de CPU"
fi

t_section "chaîne de démarrage"
chain_rc=0
bash -s -- "${T_ROOT}" << 'CHAIN' || chain_rc=$?
set -euo pipefail
root="$1"
conf="${root}/service/cron/configure.sh"
chain="${root}/config/cron/w-boot-chain.service"
boot_timer="${root}/config/cron/w-boot-chain.timer"
idle_timer="${root}/config/cron/w-idle-scan.timer"
reboot_timer="${root}/config/cron/w-reboot-notice.timer"
units="${root}/config/cron"
grep -qF 'ExecStart=-${systemctl_bin} start --wait w-boot-scan.service' "${chain}"
grep -qF 'ExecStart=-${systemctl_bin} start --wait w-idle-scan.service' "${chain}"
grep -qF 'ExecStart=-${systemctl_bin} start --wait w-reboot-notice.service' "${chain}"
grep -q 'is-failed --quiet' "${chain}"
grep -q 'core/log/log.sh' "${conf}"
timers="${root}/config/cron/timers.conf"
grep -q 'OnBootSec=${BOOT_ON_BOOT_SEC}' "${boot_timer}"
grep -q 'BOOT_ON_BOOT_SEC=0' "${timers}"
grep -q 'OnUnitActiveSec=${IDLE_EVERY}' "${idle_timer}"
grep -q 'IDLE_EVERY=1h' "${timers}"
grep -q 'OnUnitActiveSec=${REBOOT_EVERY}' "${reboot_timer}"
grep -q 'REBOOT_EVERY=6h' "${timers}"
grep -q 'Persistent=${TIMER_PERSISTENT}' "${boot_timer}"
grep -q 'Persistent=${TIMER_PERSISTENT}' "${idle_timer}"
grep -q 'Persistent=${TIMER_PERSISTENT}' "${reboot_timer}"
grep -q 'TIMER_PERSISTENT=false' "${timers}"
grep -q 'w-boot-chain.timer' "${conf}"
test -f "${root}/script/boot-check.sh"
grep -q 'systemctl disable --now w-boot-scan.timer' "${conf}"
! grep -q 'OnBootSec=2min' "${conf}" "${timers}" "${units}"/*.service "${units}"/*.timer
! grep -q 'OnBootSec=15min' "${conf}" "${timers}" "${units}"/*.service "${units}"/*.timer
! grep -q 'OnBootSec=20min' "${conf}" "${timers}" "${units}"/*.service "${units}"/*.timer
! grep -q 'Persistent=true' "${conf}" "${timers}" "${units}"/*.service "${units}"/*.timer
grep -q 'w-boot-chain.timer' "${root}/script/verify/alerts.sh"
grep -q 'w-boot-chain.timer' "${root}/script/verify/workstation.sh"
grep -q 'PERIODIC_EVERY=2h' "${timers}"
grep -q 'OnBootSec=${PERIODIC_ON_BOOT_SEC}' "${root}/config/cron/w-periodic-scan.timer"
grep -q 'OnUnitActiveSec=${PERIODIC_EVERY}' "${root}/config/cron/w-periodic-scan.timer"
grep -q 'Persistent=${TIMER_PERSISTENT}' "${root}/config/cron/w-periodic-scan.timer"
grep -q 'w-periodic-scan.timer' "${conf}"
grep -q 'w-periodic-scan.timer' "${root}/script/verify/alerts.sh"
grep -q 'w-periodic-scan.timer' "${root}/script/verify/workstation.sh"
grep -q 'HOURLY_EVERY=1h' "${timers}"
grep -q 'HOURLY_ON_BOOT_SEC=1h' "${timers}"
grep -q 'OnBootSec=${HOURLY_ON_BOOT_SEC}' "${root}/config/cron/w-hourly-scan.timer"
grep -q 'OnUnitActiveSec=${HOURLY_EVERY}' "${root}/config/cron/w-hourly-scan.timer"
grep -q 'Persistent=${TIMER_PERSISTENT}' "${root}/config/cron/w-hourly-scan.timer"
grep -q 'w-hourly-scan.timer' "${conf}"
grep -q 'w-hourly-scan.timer' "${root}/script/verify/alerts.sh"
grep -q 'w-hourly-scan.timer' "${root}/script/verify/workstation.sh"
awk '
    /aide.sh/ { if (!a) a = NR }
    /rkhunter.sh/ { if (a && !b) b = NR }
    /chkrootkit.sh/ { if (b && !c) c = NR }
    /debsums.sh/ { if (c && !d) d = NR }
    END { exit (a && b && c && d && a < b && b < c && c < d) ? 0 : 1 }
' "${root}/service/cron/watchdogs/hourly-scan.sh"
grep -q 'boot-check.sh' "${root}/script/verify/boot.sh"
test -f "${root}/script/boot-check.sh"
grep -q '39f53479d3a045ac8e11786248231fbf' "${root}/script/boot-check.sh"
grep -q 'be02cf6855d2428ba40df7e9d022f03d' "${root}/script/boot-check.sh"
grep -q 'd9b373ed55a64feb8242e02dbe79a49c' "${root}/script/boot-check.sh"
grep -q 'src/config/global.conf' "${root}/script/boot-check.sh"
CHAIN
if [[ "${chain_rc}" -eq 0 ]]; then
    t_pass "graph.boot.chain" "chaîne sans délai fixe, contrôle manuel installé"
else
    t_fail "graph.boot.chain" "la chaîne doit enchaîner les trois passes, et le contrôle doit lire le journal si l'heure de début a disparu"
fi

logs_ok=1
common="${T_ROOT}/service/cron/watchdogs/common.sh"
server_boot="${T_ROOT}/../server/service/cron/watchdogs/boot-scan.sh"
shared_chain="${T_ROOT}/../share/service/cron/watchdogs/chain.sh"
grep -q 'LOG_DIR="${BASE}/cron/security_logs"' "${common}" || logs_ok=0
grep -q 'ALERT_DIR="${BASE}/cron/alerts"' "${common}" || logs_ok=0
grep -q 'LOG_DIR="${CONFIG_BASE_DIRECTORY}/cron/security_logs"' "${server_boot}" || logs_ok=0
grep -q 'ALERT_DIR="${CONFIG_BASE_DIRECTORY}/cron/alerts"' "${server_boot}" || logs_ok=0
grep -q 'cron/security_logs' "${shared_chain}" || logs_ok=0
if grep -q '/var/lib/liltress-workstation/watchdog' "${common}"; then
    logs_ok=0
fi
if grep -q '/var/lib/liltress-server/watchdog' "${server_boot}"; then
    logs_ok=0
fi
if [[ "${logs_ok}" -eq 1 ]]; then
    t_pass "graph.logs.same-dir" "journaux et alertes sous cron"
else
    t_fail "graph.logs.same-dir" "le lecteur et les deux produits ne désignent pas cron"
fi

t_section "alerte de plantage et incident"
crash_rc=0
bash -s -- "${T_ROOT}" << 'CRASH' || crash_rc=$?
set -euo pipefail
root="$1"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir -p "${work}/cron/bin" "${work}/bin"
cat > "${work}/cron/mail.conf" << EOF
MAIL_ALERTS="1"
WATCHDOG_MAIL="alerts@example.com"
PROJECT_NAME="Liltress Workstation"
EOF
cat > "${work}/cron/bin/send.sh" << 'EOF'
#!/usr/bin/env bash
printf '%s\n----\n' "${CONTENT}" >> "${SENT}"
EOF
chmod 755 "${work}/cron/bin/send.sh"
cat > "${work}/bin/clamscan" << 'EOF'
#!/usr/bin/env bash
for f in "$@"; do
    [[ "${f}" == "--" ]] && continue
    printf 'scan %s\n' "${f}" >> "${SEEN}"
    case "${f}" in
        *bad*) kill -s SEGV $$ ;;
        *virus*) printf '%s: Eicar-Test-Signature FOUND\n' "${f}"; exit 1 ;;
    esac
done
exit 0
EOF
chmod 755 "${work}/bin/clamscan"
export BASE="${work}" SENT="${work}/sent.txt" SEEN="${work}/seen.txt" PATH="${work}/bin:${PATH}"
# shellcheck disable=SC1091
source "${root}/service/cron/watchdogs/common.sh"
sentence="$(get_crash_sentence "AIDE" 139)"
printf '%s' "${sentence}" | grep -q 'signal 11'
printf '%s' "${sentence}" | grep -q 'erreur interne du programme'
LOG_FILE="${work}/clam.log"
ALERT_FILE="${work}/clam.txt"
: > "${LOG_FILE}"
list="${work}/list"
printf '/ok\0/bad\0/virus\0/after\0' > "${list}"
list_clamav_scan "${list}" >> "${LOG_FILE}" 2>&1
grep -q 'clamscan planté signal 11 sur /bad' "${LOG_FILE}"
grep -q 'scan /after' "${SEEN}"
report_clamav
kind="$(get_clamav_kind "${LOG_FILE}")"
[[ "${kind}" == "infected" ]]
log_alert "clamscan : infection(s) (voir ${LOG_FILE})"
grep -q 'Ce fichier n'"'"'a pas été analysé' "${SENT}"
grep -q 'clamscan planté signal 11 sur /bad' "${SENT}"
grep -q 'clamscan : infection(s)' "${SENT}"
grep -q 'Eicar-Test-Signature FOUND' "${SENT}"
: > "${SEEN}"
: > "${LOG_FILE}"
: > "${SENT}"
printf '/bad1\0/bad2\0/later\0' > "${list}"
list_clamav_scan "${list}" >> "${LOG_FILE}" 2>&1
grep -q 'contrôle arrêté' "${LOG_FILE}"
! grep -q 'scan /later' "${SEEN}"
report_clamav
grep -q 'deux fois de suite' "${SENT}"
grep -q 'fichiers restants n'"'"'ont pas été analysés' "${SENT}"
: > "${list}"
: > "${LOG_FILE}"
: > "${SENT}"
empty_rc=0
set +e
list_clamav_scan "${list}" >> "${LOG_FILE}" 2>&1
empty_rc=$?
set -e
[[ "${empty_rc}" -eq 0 ]]
[[ ! -s "${SENT}" ]]
: > "${SENT}"
bash -c '
set -euo pipefail
export BASE="'"${work}"'" SENT="'"${SENT}"'"
source "'"${root}"'/service/cron/watchdogs/common.sh"
LOG_FILE="'"${work}"'/dead.log"
ALERT_FILE="'"${work}"'/dead.txt"
: > "${LOG_FILE}"
arm_crash_mail "essai"
exit 3
' || true
grep -q "s'est arrêté (code 3)" "${SENT}"
CRASH
if [[ "${crash_rc}" -eq 0 ]]; then
    t_pass "graph.crash-mail" "plantage nommé, suite du lot, infection encore signalée"
else
    t_fail "graph.crash-mail" "le courrier de plantage ou d'infection n'a pas le texte attendu"
fi

t_section "durcissement quotidien"
ssh_drop="${T_ROOT}/config/ssh/00-liltress-workstation.conf"
ufw_policy="${T_ROOT}/config/ufw/policy.conf"
usb="${T_ROOT}/service/usbguard/configure.sh"
reboot="${T_ROOT}/service/cron/watchdogs/reboot-notice.sh"
daily_ok=1
grep -q '^AllowTcpForwarding no$' "${ssh_drop}" || daily_ok=0
grep -q '^AllowAgentForwarding no$' "${ssh_drop}" || daily_ok=0
grep -q '^PasswordAuthentication yes$' "${ssh_drop}" || daily_ok=0
grep -q 'timestamp_timeout=5' "${T_ROOT}/system/pam/configure.sh" || daily_ok=0
grep -q 'pgrep -x' "${reboot}" || daily_ok=0
if grep -qE 'systemctl reboot|shutdown' "${reboot}"; then
    daily_ok=0
fi
grep -q '03:\*:\*' "${usb}" || daily_ok=0
if grep -q 'usb-storage' "${usb}"; then
    daily_ok=0
fi
grep -q 'authorized_keys' "${T_ROOT}/../share/python/aide-home.py" || daily_ok=0
grep -q '!/home/' "${T_ROOT}/config/aide/aide.conf" || daily_ok=0
awk '
    $1 == "/etc" { etc = NR }
    $0 == "!/etc/crowdsec/hub/.index.json" { ex = NR }
    END { exit !(etc && ex && ex > etc) }
' "${T_ROOT}/config/aide/aide.conf" || daily_ok=0
awk '
    /__HF_BASE__/ && /All/ { base = NR }
    $0 == "!__HF_BASE__/cron/[^/]+\\.stamp$" { stamp = NR }
    $0 == "!__HF_BASE__/cron/integrity\\.sha256$" { integ = NR }
    $0 == "!__HF_BASE__/cron/rkhunter-mirrors\\.sha256$" { mirrors = NR }
    END { exit !(base && stamp > base && integ > stamp && mirrors > integ) }
' "${T_ROOT}/config/aide/aide.conf" || daily_ok=0
awk '
    /out\.extend/ { ext = NR }
    /path\.write_text/ { wr = NR }
    END { exit !(ext && wr && wr > ext) }
' "${T_ROOT}/../share/python/aide-home.py" || daily_ok=0
grep -q 'w-reboot-notice.timer' "${T_ROOT}/service/cron/configure.sh" || daily_ok=0
grep -q 'scope global' "${T_ROOT}/service/ufw/configure.sh" || daily_ok=0
grep -q 'SSH LAN' "${ufw_policy}" || daily_ok=0
grep -q 'UFW_DEFAULT_OUTGOING=allow' "${ufw_policy}" || daily_ok=0
grep -qF 'ufw default "${UFW_DEFAULT_OUTGOING}" outgoing' "${T_ROOT}/service/ufw/configure.sh" || daily_ok=0
for lang in en fr de es; do
    page="${T_ROOT}/doc/${lang}/README.md"
    grep -q 'AllowTcpForwarding no' "${page}" || daily_ok=0
    grep -q 'AllowAgentForwarding no' "${page}" || daily_ok=0
    grep -q 'PasswordAuthentication yes' "${page}" || daily_ok=0
    grep -q 'w-reboot-notice.timer' "${page}" || daily_ok=0
    grep -q 'usbguard' "${page}" || daily_ok=0
done
if grep -q 'No other incoming allow rule is added.' "${T_ROOT}/doc/en/README.md"; then
    daily_ok=0
fi
ver="${T_ROOT}/script/verify/workstation.sh"
grep -q 'allowtcpforwarding' "${ver}" || daily_ok=0
grep -q 'allowagentforwarding' "${ver}" || daily_ok=0
grep -qF 'SSH (limit)' "${ver}" || daily_ok=0
grep -qF 'SSH LAN' "${ver}" || daily_ok=0
grep -q 'timestamp_timeout=5' "${ver}" || daily_ok=0
grep -q 'w-reboot-notice.timer' "${ver}" || daily_ok=0
grep -qF 'allow with-interface equals { 03:*:* }' "${ver}" || daily_ok=0
grep -qF 'The same pass checks SSH forwarding' "${T_ROOT}/doc/en/README.md" || daily_ok=0
grep -qF 'La même passe contrôle le relais SSH' "${T_ROOT}/doc/fr/README.md" || daily_ok=0
grep -qF 'Derselbe Lauf prüft die SSH-Weiterleitung' "${T_ROOT}/doc/de/README.md" || daily_ok=0
grep -qF 'La misma pasada comprueba el reenvío SSH' "${T_ROOT}/doc/es/README.md" || daily_ok=0
if [[ "${daily_ok}" -eq 1 ]]; then
    t_pass "graph.daily" "relais SSH coupé, préfixes connectés, USB, avis de redémarrage"
else
    t_fail "graph.daily" "le durcissement quotidien doit rester compatible avec le poste"
fi

t_section "readme"
readme="${T_ROOT}/README.md"
en="${T_ROOT}/doc/en/README.md"
fr="${T_ROOT}/doc/fr/README.md"
pages_ok=1
for lang in en fr de es; do
    if [[ ! -f "${T_ROOT}/doc/${lang}/README.md" ]]; then
        pages_ok=0
    fi
    for page in configuration.md surveillance.md architecture.md files.md logs.md; do
        if [[ -f "${T_ROOT}/doc/${lang}/${page}" ]]; then
            pages_ok=0
        fi
    done
done
for old in configuration.md surveillance.md architecture.md files.md logs.md; do
    [[ -f "${T_ROOT}/${old}" ]] && pages_ok=0
done
grep -qF '## Documentation' "${readme}" || pages_ok=0
grep -qF 'Click a flag to open all the information.' "${readme}" || pages_ok=0
grep -qF 'https://raw.githubusercontent.com/palarchsys/liltress-workstation/main/script/install.sh' "${readme}" || pages_ok=0
grep -qF 'ca-certificates curl git swaks tar' "${readme}" || pages_ok=0
grep -qF 'sudo apt-get update' "${readme}" || pages_ok=0
grep -qF 'git clone https://github.com/palarchsys/liltress-workstation' "${readme}" && pages_ok=0
grep -qF 'Do not copy it into a message, a ticket, or a repository.' "${readme}" && pages_ok=0
for flag in en fr de es; do
    [[ -f "${T_ROOT}/doc/flags/${flag}.svg" ]] || pages_ok=0
    grep -qF "doc/flags/${flag}.svg" "${readme}" || pages_ok=0
    grep -q 'width="90" height="60" viewBox="0 0 90 60"' "${T_ROOT}/doc/flags/${flag}.svg" || pages_ok=0
done
grep -qF 'Liltress Workstation prepares an Ubuntu 26.04 or newer workstation.' "${readme}" || pages_ok=0
grep -qF 'Liltress Workstation prepares an Ubuntu 26.04 or newer workstation.' "${en}" || pages_ok=0
grep -qF 'It installs the local DNS resolver, the firewall, and the security checks.' "${readme}" || pages_ok=0
grep -qF 'It installs the local DNS resolver, the firewall, and the security checks.' "${en}" || pages_ok=0
if grep -qF 'Liltress Workstation' "${readme}" \
   && grep -qF 'https://raw.githubusercontent.com/palarchsys/liltress-workstation/main/script/install.sh' "${en}" \
   && grep -qF 'ca-certificates curl git swaks tar' "${en}" \
   && grep -qF 'doc/en/README.md' "${readme}" \
   && grep -qF 'doc/fr/README.md' "${readme}" \
   && grep -qF 'doc/de/README.md' "${readme}" \
   && grep -qF 'doc/es/README.md' "${readme}" \
   && ! grep -qF '## Avant de commencer' "${readme}" \
   && ! grep -R -qF 'disable_ipv6' "${T_ROOT}/docs" \
   && ! grep -R -qF 'PasswordAuthentication no' "${T_ROOT}/docs" \
   && grep -qF 'Ne le copiez pas dans un message, un ticket ou un dépôt.' "${fr}" \
   && grep -qF 'LYNIS_MIN_SCORE' "${en}" \
   && grep -qF 'is 80' "${en}" \
   && awk '
        /^## 📋 Before you start$/ { h[++n] = NR }
        /^## 📋 Installation$/ { h[++n] = NR }
        /^## What configure.sh does$/ { h[++n] = NR }
        /^## Installed software and services$/ { h[++n] = NR }
        /^## 📋 Alert emails$/ { h[++n] = NR }
        /^## 📋 Commands after installation$/ { h[++n] = NR }
        END {
            if (n != 6) exit 1
            for (i = 2; i <= n; i++) if (h[i] <= h[i-1]) exit 1
        }
      ' "${en}" \
   && awk '
        /^## 📋 Avant de commencer$/ { h[++n] = NR }
        /^## 📋 Installation$/ { h[++n] = NR }
        /^## Action de configure.sh$/ { h[++n] = NR }
        /^## Logiciels et services installés$/ { h[++n] = NR }
        /^## 📋 E-mails d'"'"'alerte$/ { h[++n] = NR }
        /^## 📋 Commandes après l'"'"'installation$/ { h[++n] = NR }
        END {
            if (n != 6) exit 1
            for (i = 2; i <= n; i++) if (h[i] <= h[i-1]) exit 1
        }
      ' "${fr}" \
   && [[ "${pages_ok}" -eq 1 ]]; then
    t_pass "graph.readme" "squelette du README et pages liées"
else
    t_fail "graph.readme" "le README du poste doit suivre agents/laws/readme.md"
fi

t_section "archive d'alerte"
alerts_ok=1
for lang in en fr de es; do
    page="${T_ROOT}/doc/${lang}/README.md"
    grep -q '/opt/liltress-workstation/cron/alerts' "${page}" || alerts_ok=0
    if grep -q 'RCLONE_ALERTS' "${page}"; then
        alerts_ok=0
    fi
    if grep -qF 'rclone.conf' "${page}"; then
        alerts_ok=0
    fi
    if grep -q 'Mode test' "${page}"; then
        alerts_ok=0
    fi
done
if grep -qF 'rclone.conf' "${T_ROOT}/README.md"; then
    alerts_ok=0
fi
if python3 "$(locate_python_dir)/install-plan.py" has-path "${T_ROOT}/config/schema/installation.json"
then
    alerts_ok=0
fi
if ! grep -q 'N|n|non' "${T_ROOT}/script/configure.sh"; then
    alerts_ok=0
fi
if grep -q 'ask_drive_alert' "${T_ROOT}/script/configure.sh"; then
    alerts_ok=0
fi
if [[ "${alerts_ok}" -eq 1 ]]; then
    t_pass "graph.alerts" "dossier d'alertes, courrier seul, sans copie distante"
else
    t_fail "graph.alerts" "le README ou configure.sh porte encore une copie distante ou le mode test"
fi

alert_rc=0
bash -s -- "${T_ROOT}" << 'ALERT' || alert_rc=$?
set -euo pipefail
root="$1"
mono="$(cd -- "${root}/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir -p "${work}/cron/bin" "${work}/bin"
cat > "${work}/cron/bin/send.sh" << 'EOF'
#!/usr/bin/env bash
printf 'sent\n' > "${SENT}"
EOF
chmod 755 "${work}/cron/bin/send.sh"
export BASE="${work}" PATH="${work}/bin:${PATH}"
export SENT="${work}/sent" RCLONE="${work}/rclone.log"
# shellcheck disable=SC1091
source "${mono}/share/core/watchdog/watchdog.sh"
LOG_FILE="${work}/sec.log"
ALERT_FILE="${work}/cron/alerts/sample.txt"
: > "${LOG_FILE}"
MAIL_ALERTS=0
RCLONE_ALERTS=0
WATCHDOG_MAIL=""
NOTE=""
NOTE_CMD=""
TITLE=""
log_alert "essai archive"
[[ -f "${ALERT_FILE}" ]]
grep -q 'essai archive' "${ALERT_FILE}"
[[ ! -e "${SENT}" ]]
[[ ! -s "${RCLONE}" ]]
RCLONE_ALERTS=1
RCLONE_REMOTE="gdrive"
RCLONE_PATH="liltress-alerts"
printf 'token\n' > "${work}/cron/rclone.conf"
log_alert "essai drive"
[[ ! -s "${RCLONE}" ]]
[[ ! -e "${SENT}" ]]
grep -q 'essai drive' "${ALERT_FILE}"
ALERT
if [[ "${alert_rc}" -eq 0 ]]; then
    t_pass "graph.alert-file" "fichier local sans courrier, ancienne variable de copie ignorée"
else
    t_fail "graph.alert-file" "l'archive locale ou une copie distante ne suit pas le réglage"
fi

t_section "surveillance du poste"
watch_rc=0
bash -s -- "${T_ROOT}" << 'WATCH' || watch_rc=$?
set -euo pipefail
root="$1"
grep -q 'ONACCESS_MOUNTS=1' "${root}/config/clamav/onaccess.conf"
! grep -q 'CLAMAV_KILL' "${root}/config/clamav/onaccess.conf"
! grep -q 'CLAMAV_KILL' "${root}/service/cron/watchdogs/clamav-response.sh"
grep -q 'kill -TERM' "${root}/service/cron/watchdogs/clamav-response.sh"
grep -q 'nft add table inet w_isolate' "${root}/service/cron/watchdogs/clamav-response.sh"
grep -q '/var/lib/clamav/quarantine' "${root}/config/clamav/onaccess.conf"
grep -q 'add_onaccess_directory /tmp' "${root}/service/clamav/configure.sh"
grep -q 'add_onaccess_directory /var/tmp' "${root}/service/clamav/configure.sh"
grep -q 'add_onaccess_directory /opt' "${root}/service/clamav/configure.sh"
! grep -q 'OnAccessIncludePath /' "${root}/service/clamav/configure.sh"
! grep -q 'OnAccessExcludePath' "${root}/service/clamav/configure.sh"
grep -q 'ONACCESS_FIXED_EXCLUDE' "${root}/service/cron/watchdogs/apply-scan-skip.sh"
grep -q 're.escape' "${root}/../share/python/scan-skip-apply.py"
grep -q 'BASE}/src' "${root}/service/cron/watchdogs/apply-scan-skip.sh"
grep -qF 'sub(/^\^/' "${root}/service/cron/watchdogs/clamav.sh"
grep -q 'mktemp -p /run/liltress-workstation' "${root}/service/cron/watchdogs/clamav.sh"
grep -q 'CLAMAV_EVENT_KIND=idle' "${root}/service/cron/watchdogs/idle-scan.sh"
grep -q 'CLAMAV_EVENT_MAIL=0' "${root}/service/cron/watchdogs/idle-scan.sh"
grep -q 'clamav-response.sh' "${root}/service/cron/watchdogs/idle-scan.sh"
grep -q 'idle) kind_label="passe différée"' "${root}/service/cron/watchdogs/clamav-response.sh"
grep -q 'infections déjà signalées' "${root}/../share/locale/fr/watchdog.txt"
awk '
    /== "infected"/ { inf = NR }
    /CLAMAV_EVENT_KIND=idle/ { if (!call) call = NR; last = NR }
    /infections-already-signal-es/ { known = NR }
    END { exit !(inf && call && known && inf < call && last < known) }
' "${root}/service/cron/watchdogs/idle-scan.sh"
grep -q 'CLAM_MODE=daemon' "${root}/service/cron/watchdogs/clamav.sh"
grep -q 'flock -n 9' "${root}/service/cron/watchdogs/clamav.sh"
! grep -q 'clamdscan' "${root}/service/cron/watchdogs/clamav.sh"
grep -q 'detect-and-apply.sh' "${root}/service/apparmor/configure.sh"
grep -q 'detect-and-apply.sh' "${root}/service/apparmor/userns.sh"
test -x "${root}/service/apparmor/detect-and-apply.sh"
grep -q 'CROWDSEC_BAN_DURATION=48h' "${root}/config/crowdsec/ban.conf"
grep -q 'run_check integrity.sh' "${root}/service/cron/watchdogs/boot-scan.sh"
grep -q 'run_check behavior.sh' "${root}/service/cron/watchdogs/boot-scan.sh"
grep -q 'run_check egress-watch.sh' "${root}/service/cron/watchdogs/boot-scan.sh"
! grep -q 'BEHAVIOR_WATCH' "${root}/service/cron/watchdogs/behavior.sh"
! grep -q 'EGRESS_LOG' "${root}/service/cron/watchdogs/egress-watch.sh"
! grep -q 'EGRESS_LOG' "${root}/service/ufw/egress.sh"
! grep -q 'EGRESS_LOG' "${root}/config/ufw/egress.conf"
grep -q 'nft add table inet w_egress' "${root}/service/ufw/egress.sh"
grep -q 'th dport 123 accept' "${root}/service/ufw/egress.sh"
grep -q 'th dport 4460 accept' "${root}/service/ufw/egress.sh"
grep -q '224.0.0.251' "${root}/service/ufw/egress.sh"
grep -q 'ff02::fb' "${root}/service/ufw/egress.sh"
grep -q 'th sport 68 th dport 67 accept' "${root}/service/ufw/egress.sh"
grep -q 'th sport 546 th dport 547 accept' "${root}/service/ufw/egress.sh"
grep -q 'th dport 161 meta pkttype' "${root}/service/ufw/egress.sh"
grep -q 'w-egress-table.service' "${root}/service/ufw/egress.sh"
grep -q 'config/integrity/paths.list' "${root}/service/cron/configure.sh"
grep -Fq 'watchdogs/." "${CONFIG_BASE_DIRECTORY}/cron/bin/"' "${root}/service/cron/configure.sh"
test -f "${root}/service/cron/watchdogs/integrity.sh"
grep -Fq '${CONFIG_BASE_DIRECTORY}/config/global.conf' "${root}/service/cron/configure.sh"
! grep -q 'NET_ISOLATE=' "${root}/config/ufw/egress.conf"
! grep -q 'NET_ISOLATE:-' "${root}/service/cron/watchdogs/clamav-response.sh"
grep -q 'NET_ISOLATE_SEC=120' "${root}/config/ufw/egress.conf"
deny_out='ufw default'
deny_out+=' deny'
deny_out+=' outgoing'
! grep -Fq "${deny_out}" "${root}/service/ufw/egress.sh"
grep -q 'ptrace' "${root}/config/auditd/tail.rules"
grep -q 'init_module' "${root}/config/auditd/tail.rules"
! grep -q 'kernel.yama.ptrace_scope' "${root}/config/auditd/tail.rules"
test -f "${root}/config/integrity/paths.list"
test ! -e "${root}/config/behavior/watch.conf"
test ! -e "${root}/config/cron/w-integrity.timer"
grep -q 'systemctl disable --now w-integrity.timer' "${root}/service/cron/configure.sh"
grep -q 'systemctl disable --now w-behavior.timer' "${root}/service/cron/configure.sh"
grep -q 'systemctl disable --now w-egress-watch.timer' "${root}/service/cron/configure.sh"
grep -q -- '-S connect' "${root}/config/auditd/tail.rules"
grep -q -- '-k w-egress' "${root}/config/auditd/tail.rules"
grep -q 'ausearch' "${root}/service/cron/watchdogs/egress-watch.sh"
grep -q 'check_egress_routine' "${root}/service/cron/watchdogs/egress-watch.sh"
grep -q 'strip_egress_routine' "${root}/service/cron/watchdogs/egress-watch.sh"
grep -q 'list_egress_suspects' "${root}/service/cron/watchdogs/egress-watch.sh"
grep -q 'flow_hold' "${root}/service/cron/watchdogs/egress-watch.sh"
grep -q '@v4 reject' "${root}/service/cron/watchdogs/egress-watch.sh"
grep -q 'flux sortant suspect bloqué' "${root}/../share/locale/fr/watchdog.txt"
grep -q 'quarantine.registry' "${root}/service/cron/watchdogs/egress-watch.sh"
! grep -q 'w_isolate' "${root}/service/cron/watchdogs/egress-watch.sh"
! grep -q 'flux sortants hors des ports 53, 80 et 443' "${root}/service/cron/watchdogs/egress-watch.sh"
grep -q 'record_quarantine_origin' "${root}/../share/core/watchdog/quarantine.sh"
grep -q 'quarantine-restore.sh' "${root}/../share/core/watchdog/quarantine.sh"
grep -q 'record_quarantine_log' "${root}/service/cron/watchdogs/rkhunter.sh"
grep -q 'record_quarantine_log' "${root}/service/cron/watchdogs/chkrootkit.sh"
grep -q 'non mis en quarantaine' "${root}/../share/locale/fr/watchdog.txt"
! grep -q 'display:flex' "${root}/template/mail.html"
! grep -q 'width:840px' "${root}/template/mail.html"
! grep -q 'min-width:100%' "${root}/template/mail.html"
! grep -q 'min-width:450px' "${root}/template/mail.html"
! grep -q 'max-width:450px' "${root}/template/mail.html"
! grep -q 'min-width:800px' "${root}/template/mail.html"
! grep -q 'min-width:400px' "${root}/template/mail.html"
! grep -q 'max-width:800px' "${root}/template/mail.html"
! grep -q 'min-height:100vh' "${root}/template/mail.html"
! grep -q 'width:max-content' "${root}/template/mail.html"
! grep -E 'white-space:pre([^-]|$)' "${root}/template/mail.html"
grep -q 'max-width:760px' "${root}/template/mail.html"
grep -q 'width:100%' "${root}/template/mail.html"
grep -q 'white-space:pre-wrap' "${root}/template/mail.html"
grep -q 'word-break:break-word' "${root}/template/mail.html"
grep -q 'overflow-x:auto' "${root}/template/mail.html"
grep -q '<pre' "${root}/template/mail.html"
grep -q 'quarantine-restore.sh' "${root}/service/cron/configure.sh"
grep -q 'mail-test.sh' "${root}/service/cron/configure.sh"
grep -q 'send_mail_test' "${root}/../share/core/mail/mail-test.sh"
WATCH
if [[ "${watch_rc}" -eq 0 ]]; then
    t_pass "graph.watch" "surveillance continue et contrôles au démarrage"
else
    t_fail "graph.watch" "la table de journal, auditd et les contrôles au démarrage doivent rester actifs"
fi

t_section "noms des fichiers de configuration"
t_check_config_name() {
    local rel="$1"
    local domain sub base stem token
    case "${rel}" in
        global.conf|user.conf|secrets.conf) return 0 ;;
        aide/aide.conf|fail2ban/jail.local|rkhunter/rkhunter.conf.local) return 0 ;;
        system/pam-configs/faillock|system/pam-configs/faillock-preauth) return 0 ;;
        ssh/00-liltress-workstation.conf) return 0 ;;
        vpn/vpn.conf|vpn/bypass.cidrs) return 0 ;;
        unattended-upgrades/20auto-upgrades|unattended-upgrades/51liltress-workstation) return 0 ;;
    esac
    if [[ "${rel}" =~ ^cron/w-[a-z][a-z0-9]*(-[a-z0-9]+)*\.(service|timer|path)$ ]]; then
        return 0
    fi
    IFS=/ read -r domain sub base <<< "${rel}"
    if [[ -z "${base}" ]]; then
        base="${sub}"
        sub=""
    elif [[ -n "${base}" && "${base}" == */* ]]; then
        return 1
    fi
    [[ "${domain}" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]] || return 1
    if [[ -n "${sub}" ]]; then
        [[ "${sub}" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]] || return 1
    fi
    [[ "${base}" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*\.(conf|list|paths|rules|ignore|yaml|json|service|timer|path|cron|keys|acl)$ ]] || return 1
    stem="${base%%.*}"
    token="${stem%%-*}"
    [[ "${token}" != "${domain}" ]]
}
config_bad=""
while IFS= read -r rel; do
    [[ -z "${rel}" ]] && continue
    if ! t_check_config_name "${rel}"; then
        config_bad="${config_bad} ${rel}"
    fi
done < <(cd -- "${T_ROOT}" && find config \( -type f -o -type l \) \
    ! -name '*.save' ! -name '*.save.conf' ! -name '*.conf.save' -printf '%P\n' | sort)
if [[ -z "${config_bad}" ]]; then
    t_pass "graph.config.names" "fichiers de configuration au gabarit"
else
    t_fail "graph.config.names" "noms hors gabarit :${config_bad}"
fi

t_section "marques Shared Server Workstation"
t_check_section_mark() {
    local file="$1"
    awk '
        /^# Shared$/ || /^# Server$/ || /^# Workstation$/ { bad = 1 }
        /^[WS]_[A-Z0-9_]+=/ { bad = 1 }
        END { exit bad ? 1 : 0 }
    ' "${file}"
}
prefix_bad=""
while IFS= read -r rel; do
    [[ -z "${rel}" ]] && continue
    if ! t_check_section_mark "${T_ROOT}/config/${rel}"; then
        prefix_bad="${prefix_bad} ${rel}"
    fi
done < <(cd -- "${T_ROOT}" && find config \( -type f -o -type l \) -printf '%P\n' | sort)
if [[ -z "${prefix_bad}" ]] \
    && grep -q '^CONFIG_BASE_DIRECTORY="/opt/liltress-workstation"$' "${T_ROOT}/config/global.conf" \
    && grep -q '^PROJECT_SLUG="liltress-workstation"$' "${T_ROOT}/config/global.conf" \
    && ! grep -q 'PROJECT_SLUG}' "${T_ROOT}/config/global.conf"; then
    t_pass "graph.prefix.order" "aucune marque Shared, Server ou Workstation"
else
    t_fail "graph.prefix.order" "marque ou préfixe :${prefix_bad}"
fi
