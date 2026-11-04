#!/usr/bin/env bash
# =============================================================================
# File       : test/suites/04_forbidden.sh
# Updated at : 2026-11-04
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
t_check_forbidden "forbid.ipv6" 'disable_ipv6[[:space:]]*='
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
