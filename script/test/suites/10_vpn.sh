#!/usr/bin/env bash
# =============================================================================
# File       : script/test/suites/10_vpn.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================


locate_python_dir() {
    local dir hops=0
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        if [[ -d "${dir}/share/python" ]]; then
            printf '%s\n' "${dir}/share/python"
            return 0
        fi
        if [[ -d "${dir}/python" ]]; then
            printf '%s\n' "${dir}/python"
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

t_section "vpn"

vpn_dir="${T_ROOT}/service/vpn"
cfg_dir="${T_ROOT}/config/vpn"

while IFS= read -r file; do
    rel="${file#"${T_ROOT}/"}"
    if bash -n "${file}" 2>"${ARTIFACTS}/vpn-bash-n.err"; then
        t_pass "vpn.syntax:${rel}" "bash -n"
    else
        t_fail "vpn.syntax:${rel}" "$(tr '\n' ' ' < "${ARTIFACTS}/vpn-bash-n.err")"
    fi
done < <(find "${vpn_dir}" -name '*.sh' -type f | sort)

if grep -q 'wireguard' "${vpn_dir}/lib.sh" && grep -q 'openvpn' "${vpn_dir}/lib.sh" \
    && grep -q 'clear_vpn_network' "${vpn_dir}/cli.sh" \
    && grep -q 'list_vpn_profiles' "${vpn_dir}/cli.sh" \
    && grep -q 'remove_vpn_profile' "${vpn_dir}/cli.sh"
then
    t_pass "vpn.layout" "dossiers par protocole, liste, retrait, réseau direct"
else
    t_fail "vpn.layout" "rangement incomplet"
fi

if grep -q 'vpn)' "${T_ROOT}/core/run/launch.sh"; then
    t_pass "vpn.launch" "branche présente"
else
    t_fail "vpn.launch" "branche absente"
fi

if python3 "$(locate_python_dir)/install-plan.py" vpn-order "${T_ROOT}/config/schema/installation.json" > "${ARTIFACTS}/vpn-order.txt" 2>&1
then
    t_pass "vpn.order" "installation.json"
else
    t_fail "vpn.order" "$(tr '\n' ' ' < "${ARTIFACTS}/vpn-order.txt")"
fi

forbid_phrase="$(printf '%s%s%s%s' 'ufw ' 'default ' 'deny ' 'outgoing')"
if grep -RInE -- "wg-quick|${forbid_phrase}|disable_ipv6|resolvconf" "${vpn_dir}" "${cfg_dir}" > "${ARTIFACTS}/vpn-forbid.txt"; then
    t_fail "vpn.forbid" "$(tr '\n' ' ' < "${ARTIFACTS}/vpn-forbid.txt" | head -c 400)"
else
    t_pass "vpn.forbid" "mots absents"
fi

if python3 "$(locate_python_dir)/check-vpn-priority.py" "${cfg_dir}/vpn.conf" "${T_ROOT}/service/ufw/egress.sh" "${vpn_dir}/lib.sh" > "${ARTIFACTS}/vpn-prio.txt" 2>&1
then
    t_pass "vpn.priority" "-150"
else
    t_fail "vpn.priority" "$(tr '\n' ' ' < "${ARTIFACTS}/vpn-prio.txt")"
fi

if grep -RIn 'ct state established,related accept' "${vpn_dir}" "${cfg_dir}" > "${ARTIFACTS}/vpn-ct.txt"; then
    t_fail "vpn.ct" "$(tr '\n' ' ' < "${ARTIFACTS}/vpn-ct.txt" | head -c 400)"
else
    t_pass "vpn.ct" "pas d'accept established"
fi

if grep -vE '^[[:space:]]*(#|$)' "${cfg_dir}/bypass.cidrs" | grep -qE '[0-9]'; then
    t_fail "vpn.template" "CIDR active"
else
    t_pass "vpn.template" "aucune CIDR active"
fi

# shellcheck disable=SC1091
source "${vpn_dir}/lib.sh"
parse_dir="${ARTIFACTS}/vpn-parse"
mkdir -p "${parse_dir}"
printf '192.168.1.0/24\n' > "${parse_dir}/lan"
printf '200.200.200.0/24\n' > "${parse_dir}/public"
printf '[192.168.1.0/24, 200.200.200.0/24]\n' > "${parse_dir}/bracket"
printf '200.200.200.0\n' > "${parse_dir}/bare"
printf '192.168.1.5/24\n' > "${parse_dir}/host"
parse_ok=1
got="$(read_vpn_bypass "${parse_dir}/lan")" || parse_ok=0
[[ "${got}" == "192.168.1.0/24" ]] || parse_ok=0
got="$(read_vpn_bypass "${parse_dir}/public")" || parse_ok=0
[[ "${got}" == "200.200.200.0/24" ]] || parse_ok=0
got="$(read_vpn_bypass "${parse_dir}/bracket")" || parse_ok=0
[[ "${got}" == $'192.168.1.0/24\n200.200.200.0/24' ]] || parse_ok=0
if (( parse_ok == 1 )); then
    t_pass "vpn.parse.accept" "trois formes"
else
    t_fail "vpn.parse.accept" "${got}"
fi

printf '192.168.1.0/24\n' > "${parse_dir}/src"
write_vpn_bypass "${parse_dir}/src" "${parse_dir}/applied"
bare_state=0
write_vpn_bypass "${parse_dir}/bare" "${parse_dir}/applied" 2>"${parse_dir}/bare.err" || bare_state=$?
host_state=0
write_vpn_bypass "${parse_dir}/host" "${parse_dir}/applied" 2>"${parse_dir}/host.err" || host_state=$?
kept="$(cat "${parse_dir}/applied")"
if [[ "${bare_state}" -ne 0 && "${host_state}" -ne 0 && "${kept}" == "192.168.1.0/24" ]] \
    && grep -q '200.200.200.0/24' "${parse_dir}/bare.err"
then
    t_pass "vpn.parse.refuse" "jeu précédent conservé"
else
    t_fail "vpn.parse.refuse" "bare=${bare_state} host=${host_state} kept=${kept}"
fi

marker="$(printf '%s%s =' 'Private' 'Key')"
printf '[Interface]\n%s not-a-real-secret\n' "${marker}" > "${ARTIFACTS}/fake-wg.conf"
printf 'remote example.invalid 1194 udp\nca ca.crt\n' > "${ARTIFACTS}/fake.ovpn"
needle="$(printf '%s%s =' 'Private' 'Key')"
if git -C "${T_ROOT}" grep -n -F -e "${needle}" -- . ':!test/output' > "${ARTIFACTS}/vpn-secret-grep.txt" 2>/dev/null; then
    t_fail "vpn.secret-grep" "$(tr '\n' ' ' < "${ARTIFACTS}/vpn-secret-grep.txt" | head -c 300)"
else
    t_pass "vpn.secret-grep" "chaîne absente du suivi"
fi
if git -C "${T_ROOT}" ls-files | grep -E '(^|/)profiles/' > "${ARTIFACTS}/vpn-profiles.txt"; then
    t_fail "vpn.profiles" "$(tr '\n' ' ' < "${ARTIFACTS}/vpn-profiles.txt")"
else
    t_pass "vpn.profiles" "aucun profil versionné"
fi

if python3 "$(locate_python_dir)/check-locale.py" vpn "${T_ROOT}/../share/locale" > "${ARTIFACTS}/vpn-keys.txt" 2>&1
then
    t_pass "vpn.keys" "quatre langues"
else
    t_fail "vpn.keys" "$(tr '\n' ' ' < "${ARTIFACTS}/vpn-keys.txt")"
fi

mode_ok=1
grep -q 'run_vpn_test' "${vpn_dir}/cli.sh" || mode_ok=0
grep -q 'run_vpn_mode_on' "${vpn_dir}/cli.sh" || mode_ok=0
grep -q 'run_vpn_mode_off' "${vpn_dir}/cli.sh" || mode_ok=0
grep -q 'run_vpn_failover' "${vpn_dir}/cli.sh" || mode_ok=0
grep -q 'clear_vpn_network' "${vpn_dir}/failover.sh" || mode_ok=0
grep -q 'restart_vpn_services' "${vpn_dir}/failover.sh" || mode_ok=0
grep -q 'restart_vpn_services' "${vpn_dir}/switch.sh" || mode_ok=0
grep -q 'check_vpn_profile_valid' "${vpn_dir}/switch.sh" || mode_ok=0
grep -q 'run_vpn_test' "${vpn_dir}/import.sh" || mode_ok=0
grep -q 'VPN_FAILOVER_TRIES' "${vpn_dir}/failover.sh" || mode_ok=0
grep -q 'VPN_FAILOVER_TIMEOUT' "${vpn_dir}/failover.sh" || mode_ok=0
grep -q 'log_info "${INSTALL_WATCHER:-BASH}" "vpn.failover.none"' "${vpn_dir}/failover.sh" || mode_ok=0
grep -q 'log_error .*vpn.failover.none' "${vpn_dir}/failover.sh" && mode_ok=0
grep -q 'meta l4proto tcp th dport' "${vpn_dir}/killswitch.sh" || mode_ok=0
grep -q 'meta l4proto tcp th sport' "${vpn_dir}/killswitch.sh" || mode_ok=0
grep -q 'meta mark set' "${vpn_dir}/killswitch.sh" || mode_ok=0
grep -q 'fwmark' "${vpn_dir}/routes.sh" || mode_ok=0
grep -q 'VPN_RULE_PRIO_SSH=45' "${cfg_dir}/vpn.conf" || mode_ok=0
grep -q 'VPN_RULE_PRIO_TUNNEL=100' "${cfg_dir}/vpn.conf" || mode_ok=0
grep -q 'VPN_FAILOVER_TRIES=3' "${cfg_dir}/vpn.conf" || mode_ok=0
grep -q 'VPN_FAILOVER_TIMEOUT=10' "${cfg_dir}/vpn.conf" || mode_ok=0
grep -q 'TimeoutStartSec=300' "${cfg_dir}/w-vpn.service" || mode_ok=0
grep -q 'w-vpn-watch.timer' "${vpn_dir}/configure.sh" || mode_ok=0
if grep -E '^[[:space:]]+up\)' "${vpn_dir}/cli.sh" || grep -E '^[[:space:]]+down\)' "${vpn_dir}/cli.sh" || grep -E '^[[:space:]]+boot\)' "${vpn_dir}/cli.sh"; then
    mode_ok=0
fi
if [[ "${mode_ok}" -eq 1 ]]; then
    t_pass "vpn.mode" "registre, reprise, SSH hors tunnel"
else
    t_fail "vpn.mode" "commande ou constante absente"
fi

state_root="${ARTIFACTS}/vpn-state-root"
mkdir -p "${state_root}"
saved_base="${CONFIG_BASE_DIRECTORY:-}"
export CONFIG_BASE_DIRECTORY="${state_root}"
# shellcheck disable=SC1091
source "${vpn_dir}/state.sh"
state_ok=1
write_vpn_state || state_ok=0
record_vpn_attempt "office" 0 || state_ok=0
first="$(show_vpn_profile_state office)" || state_ok=0
[[ "$(printf '%s\n' "${first}" | sed -n '1p')" == "false" ]] || state_ok=0
[[ -z "$(printf '%s\n' "${first}" | sed -n '2p')" ]] || state_ok=0
[[ -n "$(printf '%s\n' "${first}" | sed -n '3p')" ]] || state_ok=0
[[ -n "$(printf '%s\n' "${first}" | sed -n '4p')" ]] || state_ok=0
sleep 1
record_vpn_attempt "office" 1 || state_ok=0
second="$(show_vpn_profile_state office)" || state_ok=0
kept_valid="$(printf '%s\n' "${second}" | sed -n '2p')"
[[ "$(printf '%s\n' "${second}" | sed -n '1p')" == "true" ]] || state_ok=0
[[ -n "${kept_valid}" ]] || state_ok=0
sleep 1
record_vpn_attempt "office" 0 || state_ok=0
third="$(show_vpn_profile_state office)" || state_ok=0
[[ "$(printf '%s\n' "${third}" | sed -n '1p')" == "false" ]] || state_ok=0
[[ "$(printf '%s\n' "${third}" | sed -n '2p')" == "${kept_valid}" ]] || state_ok=0
[[ "$(printf '%s\n' "${third}" | sed -n '4p')" != "$(printf '%s\n' "${second}" | sed -n '4p')" ]] || state_ok=0
if check_vpn_profile_valid office; then
    state_ok=0
fi
if [[ -n "${saved_base}" ]]; then
    export CONFIG_BASE_DIRECTORY="${saved_base}"
else
    unset CONFIG_BASE_DIRECTORY
fi
if [[ "${state_ok}" -eq 1 ]]; then
    t_pass "vpn.state" "dates conservées, essai encore accepté"
else
    t_fail "vpn.state" "registre ${third}"
fi

# shellcheck disable=SC1091
source "${vpn_dir}/import.sh"
import_root="${ARTIFACTS}/vpn-import-root"
import_src="${ARTIFACTS}/vpn-import-src"
rm -rf "${import_root}" "${import_src}"
mkdir -p "${import_src}" "${import_root}"
printf 'ca-body\n' > "${import_src}/ca.crt"
printf 'cert-body\n' > "${import_src}/client.crt"
printf 'key-body\n' > "${import_src}/client.key"
printf 'crl-body\n' > "${import_src}/crl.pem"
printf 'alice\nbob\n' > "${import_src}/auth.txt"
printf '#!/bin/sh\nexit 0\n' > "${import_src}/client.up"
cat > "${import_src}/openvpn.ovpn" << 'EOF'
client
remote 203.0.113.10 443
proto udp
auth-user-pass
comp-lzo
up client.up
redirect-gateway def1
ca "ca.crt"
cert client.crt
key client.key
crl-verify crl.pem
EOF
saved_import="${CONFIG_BASE_DIRECTORY:-}"
export CONFIG_BASE_DIRECTORY="${import_root}"
import_ok=1
if ! install_vpn_openvpn "cg-usa" "${import_src}/openvpn.ovpn"; then
    import_ok=0
fi
import_profile="${import_root}/vpn/openvpn/cg-usa"
for import_file in source runtime ca.crt client.crt client.key crl.pem auth.txt meta; do
    [[ -f "${import_profile}/${import_file}" ]] || import_ok=0
done
grep -q 'auth-user-pass auth.txt' "${import_profile}/runtime" || import_ok=0
grep -q 'ca ca.crt' "${import_profile}/runtime" || import_ok=0
grep -q 'crl-verify crl.pem' "${import_profile}/runtime" || import_ok=0
grep -q 'remote 203.0.113.10 443 udp' "${import_profile}/runtime" || import_ok=0
grep -q 'alice' "${import_profile}/auth.txt" || import_ok=0
grep -q 'comp-lzo' "${import_profile}/runtime" && import_ok=0
grep -q '^up ' "${import_profile}/runtime" && import_ok=0
[[ -e "${import_profile}/client.up" ]] && import_ok=0
printf 'only-name\n' > "${import_src}/openvpn.ovpn"
printf 'ca missing.crt\nremote 203.0.113.10 1194\nproto udp\n' > "${import_src}/openvpn.ovpn"
if ( install_vpn_openvpn "cg-miss" "${import_src}/openvpn.ovpn" ); then
    import_ok=0
fi
[[ -d "${import_root}/vpn/openvpn/cg-miss" ]] && import_ok=0
: > "${import_src}/auth.txt"
cat > "${import_src}/bare.ovpn" << 'EOF'
client
remote 203.0.113.11 1194
proto udp
auth-user-pass
EOF
if ! install_vpn_openvpn "cg-wait" "${import_src}/bare.ovpn"; then
    import_ok=0
fi
wait_auth="${import_root}/vpn/openvpn/cg-wait/auth.txt"
[[ -f "${wait_auth}" ]] || import_ok=0
if check_vpn_auth_file "${wait_auth}"; then
    import_ok=0
fi
wg_src="${ARTIFACTS}/vpn-import-wg.conf"
{
    printf '%s\n' '[Interface]'
    printf '%s%s = %s\n' 'Private' 'Key' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa='
    printf '%s\n' 'Address = 10.66.0.2/32'
    printf '%s\n' 'DNS = 1.1.1.1'
    printf '%s\n' '[Peer]'
    printf '%s\n' 'PublicKey = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb='
    printf '%s\n' 'Endpoint = 203.0.113.20:51820'
    printf '%s\n' 'AllowedIPs = 0.0.0.0/0'
} > "${wg_src}"
if ! install_vpn_wireguard "mullvad" "${wg_src}"; then
    import_ok=0
fi
wg_profile="${import_root}/vpn/wireguard/mullvad"
[[ -f "${wg_profile}/source" && -f "${wg_profile}/runtime" ]] || import_ok=0
grep -q 'Table = off' "${wg_profile}/runtime" || import_ok=0
grep -q 'DNS' "${wg_profile}/runtime" && import_ok=0
grep -q '203.0.113.20:51820' "${wg_profile}/runtime" || import_ok=0
if [[ -n "${saved_import}" ]]; then
    export CONFIG_BASE_DIRECTORY="${saved_import}"
else
    unset CONFIG_BASE_DIRECTORY
fi
if [[ "${import_ok}" -eq 1 ]]; then
    t_pass "vpn.import.files" "certificats, auth.txt et WireGuard"
else
    t_fail "vpn.import.files" "copie incomplète"
fi
