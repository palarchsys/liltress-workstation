#!/usr/bin/env bash
# =============================================================================
# File       : script/test/suites/04_forbidden.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================

t_section "interdits poste"
MONO="$(cd -- "${T_ROOT}/.." && pwd)"

t_get_forbidden_hit() {
    local pattern="$1"
    grep -RInE --include='*.sh' --include='*.conf' --include='*.service' "${pattern}" "${T_ROOT}" \
        | grep -vE ':[0-9]+:[[:space:]]*#' || true
}

t_check_forbidden() {
    local id="$1"
    local pattern="$2"
    local hits
    hits="$(t_get_forbidden_hit "${pattern}")"
    if [[ -n "${hits}" ]]; then
        t_fail "${id}" "$(printf '%s' "${hits}" | tr '\n' ' ' | head -c 500)"
    else
        t_pass "${id}" "aucune ligne active"
    fi
}
t_check_forbidden "forbid.password-no" '^[[:space:]]*PasswordAuthentication[[:space:]]+no([[:space:]]|$)'
t_check_forbidden "forbid.allowusers" '^[[:space:]]*AllowUsers[[:space:]]'
t_check_forbidden "forbid.ufw-out" 'ufw[[:space:]]+default[[:space:]]+deny[[:space:]]+outgoing'
t_check_forbidden "forbid.ufw-reset" 'ufw[[:space:]]+--force[[:space:]]+reset'
sysctl_file="${T_ROOT}/system/sysctl/configure.sh"
if grep -qF 'net.ipv6.conf.all.disable_ipv6 = 1' "${sysctl_file}" \
    && grep -qF 'net.ipv6.conf.default.disable_ipv6 = 1' "${sysctl_file}" \
    && grep -qF 'kernel.yama.ptrace_scope = 1' "${sysctl_file}" \
    && ! grep -qE 'unprivileged_userns_clone[[:space:]]*=[[:space:]]*0' "${sysctl_file}" \
    && grep -qF 'UFW_IPV6=no' "${T_ROOT}/config/ufw/policy.conf"; then
    t_pass "require.ipv6-off" "sysctl et UFW coupent IPv6"
else
    t_fail "require.ipv6-off" "IPv6 poste non coupé par défaut"
fi
resolver="${T_ROOT}/config/unbound/resolver.conf"
resolved="${T_ROOT}/config/unbound/resolved.conf"
if grep -qF 'interface: 127.0.0.1' "${resolver}" \
    && ! grep -qF 'interface: ::1' "${resolver}" \
    && grep -qF 'do-ip6: no' "${resolver}" \
    && grep -qF 'DNS=127.0.0.1' "${resolved}" \
    && ! grep -qF 'DNS=::1' "${resolved}" \
    && ! grep -qF '::1' "${T_ROOT}/service/unbound/configure.sh" \
    && ! grep -qF '::1' "${T_ROOT}/service/unbound/nm-dispatcher.sh"; then
    t_pass "require.unbound-ipv4" "Unbound écoute 127.0.0.1"
else
    t_fail "require.unbound-ipv4" "Unbound écoute encore ::1"
fi
dns_sh="${T_ROOT}/service/unbound/dns.sh"
cfg_sh="${T_ROOT}/service/unbound/configure.sh"
run_sh="${T_ROOT}/script/run.sh"
crowd_sh="${MONO}/share/service/crowdsec/install.sh"
dns_ok=1
grep -q '^clear_dns_override()' "${dns_sh}" || dns_ok=0
grep -q '^apply_unbound_dns()' "${dns_sh}" || dns_ok=0
grep -q 'clear_dns_override' "${run_sh}" || dns_ok=0
awk '
    /ready=0/ { seen = 1 }
    seen && /clear_dns_override/ { cleared = 1 }
    seen && /apply_unbound_dns/ { applied = 1 }
    END { exit !(cleared && applied) }
' "${cfg_sh}" || dns_ok=0
grep -q 'ipv4.dns 127.0.0.1' "${cfg_sh}" && dns_ok=0
grep -q '/dev/tcp/127.0.0.1/53' "${T_ROOT}/service/unbound/nm-dispatcher.sh" || dns_ok=0
grep -q 'rm -f "${CROWDSEC_KEY}"' "${crowd_sh}" && dns_ok=0
grep -q 'packagecloud.io' "${crowd_sh}" || dns_ok=0
if [[ "${dns_ok}" -eq 1 ]]; then
    t_pass "require.dns-after-unbound" "DNS local seulement si Unbound écoute"
else
    t_fail "require.dns-after-unbound" "le DNS 127.0.0.1 précède Unbound"
fi
ipv6_hits="$(t_get_forbidden_hit 'disable_ipv6[[:space:]]*=' \
    | grep -v 'system/sysctl/configure.sh:' \
    | grep -v '/script/test/' || true)"
if [[ -n "${ipv6_hits}" ]]; then
    t_fail "forbid.ipv6-elsewhere" "$(printf '%s' "${ipv6_hits}" | tr '\n' ' ' | head -c 500)"
else
    t_pass "forbid.ipv6-elsewhere" "aucune autre ligne"
fi
t_check_forbidden "forbid.usb" '(^|[[:space:]])(blacklist|install)[[:space:]]+usb-storage'
tmp_hits="$(t_get_forbidden_hit '/tmp[^#]*noexec|noexec[^#]*/tmp' | grep -v '/verify/' | grep -v 'est noexec' || true)"
if [[ -n "${tmp_hits}" ]]; then
    t_fail "forbid.tmp-noexec" "$(printf '%s' "${tmp_hits}" | tr '\n' ' ' | head -c 500)"
else
    t_pass "forbid.tmp-noexec" "aucune ligne active"
fi

chpasswd_hits="$(grep -RIn --include='*.sh' --exclude-dir=test 'chpasswd' "${T_ROOT}" \
    | grep -vE ':[0-9]+:[[:space:]]*#' \
    | grep -v '\*chpasswd\*' \
    | grep -v 'aucun chpasswd' \
    | grep -v 'jamais chpasswd' || true)"
if [[ -n "${chpasswd_hits}" ]]; then
    t_fail "forbid.chpasswd" "$(printf '%s' "${chpasswd_hits}" | tr '\n' ' ' | head -c 500)"
else
    t_pass "forbid.chpasswd" "pas d'appel chpasswd"
fi

if grep -RInE --include='*.sh' 'chmod[[:space:]]+700[[:space:]]+.*(gcc|g\+\+|/usr/bin/cc)' "${T_ROOT}" | grep -vE ':[0-9]+:[[:space:]]*#' | grep -q .; then
    t_fail "forbid.compiler-700" "chmod 700 sur un compilateur"
else
    t_pass "forbid.compiler-700" "compilateurs non verrouillés"
fi

if [[ -f "${MONO}/server/service/ssh/00-liltress-workstation.conf" || -f "${MONO}/server/config/ssh/00-liltress-workstation.conf" ]]; then
    t_fail "forbid.dropin-on-server" "le drop-in poste est dans server/service/ssh"
else
    t_pass "forbid.dropin-on-server" "drop-in poste absent du serveur"
fi
if grep -q '^PasswordAuthentication yes$' "${MONO}/server/config/ssh/sshd.conf" 2>/dev/null; then
    t_fail "forbid.server-ssh-password" "le sshd serveur accepte le mot de passe"
else
    t_pass "forbid.server-ssh-password" "sshd serveur sans mot de passe"
fi
