#!/usr/bin/env bash
# =============================================================================
# File       : script/test/suites/10_vpn.sh
# Updated at : 2026-11-14
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
if git -C "${T_ROOT}" grep -n -F -e "${needle}" -- . ':!test/output' ':!doc/examples' > "${ARTIFACTS}/vpn-secret-grep.txt" 2>/dev/null; then
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
brand_cg="${ARTIFACTS}/vpn-brand-cg"
rm -rf "${brand_cg}"
mkdir -p "${brand_cg}"
cp -a "${import_src}/ca.crt" "${import_src}/client.crt" "${import_src}/client.key" "${import_src}/auth.txt" "${brand_cg}/"
cat > "${brand_cg}/openvpn.ovpn" << 'EOF'
client
remote 203.0.113.10 443
proto udp
auth-user-pass
ca ca.crt
cert client.crt
key client.key
EOF
saved_import="${CONFIG_BASE_DIRECTORY:-}"
export CONFIG_BASE_DIRECTORY="${import_root}"
export VPN_IMPORT_STAGE_ONLY=1
import_ok=1
if ! install_vpn_openvpn "cg-usa" "${import_src}/openvpn.ovpn"; then
    import_ok=0
fi
import_profile="${VPN_STAGE_DIR}"
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
[[ -d "${import_root}/vpn/openvpn/cg-usa" ]] && import_ok=0
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
if ( install_vpn_openvpn "cg-wait" "${import_src}/bare.ovpn" ); then
    import_ok=0
fi
[[ -d "${import_root}/vpn/openvpn/cg-wait" ]] && import_ok=0
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
wg_profile="${VPN_STAGE_DIR}"
[[ -f "${wg_profile}/source" && -f "${wg_profile}/runtime" ]] || import_ok=0
grep -q 'Table = off' "${wg_profile}/runtime" || import_ok=0
grep -q 'DNS' "${wg_profile}/runtime" && import_ok=0
grep -q '203.0.113.20:51820' "${wg_profile}/runtime" || import_ok=0
[[ -d "${import_root}/vpn/wireguard/mullvad" ]] && import_ok=0
if [[ "${import_ok}" -eq 1 ]]; then
    t_pass "vpn.import.files" "copie en attente, auth vide refusé"
else
    t_fail "vpn.import.files" "copie incomplète"
fi

brand_mu="${ARTIFACTS}/vpn-brand-mu"
brand_gap="${ARTIFACTS}/vpn-brand-gap"
brand_zip="${ARTIFACTS}/vpn-brand-replace.zip"
rm -rf "${brand_mu}" "${brand_gap}"
mkdir -p "${brand_mu}" "${brand_gap}"
cp -a "${wg_src}" "${brand_mu}/config.conf"
cp -a "${brand_cg}/openvpn.ovpn" "${brand_cg}/ca.crt" "${brand_cg}/client.crt" "${brand_cg}/auth.txt" "${brand_gap}/"
python3 - "${brand_zip}" << 'PY'
import sys
import zipfile
path = sys.argv[1]
with zipfile.ZipFile(path, "w") as archive:
    archive.writestr("config.ovpn", "remote 203.0.113.10 1194\nauth-user-pass\nREPLACE\n")
    archive.writestr("auth.txt", "alice\nbob\n")
PY
brand_ok=1
if ! install_vpn_bundle openvpn cyberghost cg-brand "${brand_cg}"; then
    brand_ok=0
fi
grep -q 'brand=cyberghost' "${VPN_STAGE_DIR}/meta" || brand_ok=0
[[ -d "${import_root}/vpn/openvpn/cg-brand" ]] && brand_ok=0
if ! install_vpn_bundle wireguard mullvad mu-brand "${brand_mu}"; then
    brand_ok=0
fi
grep -q 'brand=mullvad' "${VPN_STAGE_DIR}/meta" || brand_ok=0
[[ -d "${import_root}/vpn/wireguard/mu-brand" ]] && brand_ok=0
VPN_IMPORT_STAGE_ONLY=0
if ( install_vpn_bundle openvpn mullvad mu-bad "${brand_mu}" ); then
    brand_ok=0
fi
[[ -d "${import_root}/vpn/openvpn/mu-bad" ]] && brand_ok=0
if ( install_vpn_bundle wireguard nordvpn nord-bad "${brand_mu}" ); then
    brand_ok=0
fi
[[ -d "${import_root}/vpn/wireguard/nord-bad" ]] && brand_ok=0
if ( install_vpn_bundle wireguard pia pia-bad "${brand_mu}" ); then
    brand_ok=0
fi
[[ -d "${import_root}/vpn/wireguard/pia-bad" ]] && brand_ok=0
if ( install_vpn_bundle openvpn cyberghost cg-gap "${brand_gap}" ); then
    brand_ok=0
fi
[[ -d "${import_root}/vpn/openvpn/cg-gap" ]] && brand_ok=0
if ( install_vpn_bundle openvpn acme acme-1 "${brand_cg}" ); then
    brand_ok=0
fi
[[ -d "${import_root}/vpn/openvpn/acme-1" ]] && brand_ok=0
if ( install_vpn_bundle openvpn nordvpn nord-rep "${brand_zip}" ); then
    brand_ok=0
fi
[[ -d "${import_root}/vpn/openvpn/nord-rep" ]] && brand_ok=0
[[ -f "${T_ROOT}/doc/examples/nordvpn.zip" ]] || brand_ok=0
if ( install_vpn_bundle openvpn nordvpn nord-ex "${T_ROOT}/doc/examples/nordvpn.zip" ); then
    brand_ok=0
fi
[[ -d "${import_root}/vpn/openvpn/nord-ex" ]] && brand_ok=0
if [[ "${brand_ok}" -eq 1 ]]; then
    t_pass "vpn.brand" "marque, refus, REPLACE"
else
    t_fail "vpn.brand" "contrôle de marque"
fi

export VPN_IMPORT_STAGE_ONLY=1
vpn_fault_log="${ARTIFACTS}/vpn-fault.log"
: > "${vpn_fault_log}"
vpn_had_log_error=0
if declare -F log_error >/dev/null 2>&1; then
    vpn_had_log_error=1
    eval "$(declare -f log_error | sed '1s/^log_error/vpn_saved_log_error/')"
fi
log_error() {
    printf '%s\n' "$*" >> "${vpn_fault_log}"
    return 0
}
wrap_zip="${ARTIFACTS}/vpn-wrap.zip"
root_zip="${ARTIFACTS}/vpn-auth-root.zip"
short_zip="${ARTIFACTS}/vpn-auth-short.zip"
two_zip="${ARTIFACTS}/vpn-two-dir.zip"
python3 - "${wrap_zip}" "${root_zip}" "${short_zip}" "${two_zip}" << 'PY'
import sys
import zipfile
wrap, root, short, two = sys.argv[1:]
ovpn = """client
remote 203.0.113.10 443
proto udp
auth-user-pass password.txt
redirect-gateway def1
ca ca.crt
cert client.crt
key client.key
"""

def add(archive, prefix, auth):
    archive.writestr(prefix + "openvpn.ovpn", ovpn)
    archive.writestr(prefix + "ca.crt", "ca-body\n")
    archive.writestr(prefix + "client.crt", "cert-body\n")
    archive.writestr(prefix + "client.key", "key-body\n")
    if auth is not None:
        archive.writestr(prefix + "auth.txt", auth)

with zipfile.ZipFile(wrap, "w") as archive:
    add(archive, "cgwrap/", "alice\nbob\n")
with zipfile.ZipFile(root, "w") as archive:
    add(archive, "cgroot/", None)
    archive.writestr("auth.txt", "alice\nbob\n")
with zipfile.ZipFile(short, "w") as archive:
    add(archive, "cgshort/", "alice\n")
with zipfile.ZipFile(two, "w") as archive:
    archive.writestr("one/openvpn.ovpn", "remote 203.0.113.10 1194\n")
    archive.writestr("two/auth.txt", "alice\nbob\n")
PY
brand_extra="${ARTIFACTS}/vpn-brand-extra"
brand_nokey="${ARTIFACTS}/vpn-brand-nokey"
rm -rf "${brand_extra}" "${brand_nokey}"
mkdir -p "${brand_extra}" "${brand_nokey}"
cp -a "${brand_cg}/openvpn.ovpn" "${brand_cg}/ca.crt" "${brand_cg}/client.crt" "${brand_cg}/client.key" "${brand_cg}/auth.txt" "${brand_extra}/"
printf 'note\n' > "${brand_extra}/readme.txt"
{
    printf '%s\n' '[Interface]'
    printf '%s%s = %s\n' 'Private' 'Key' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa='
    printf '%s\n' 'Address = 10.66.0.2/32'
    printf '%s\n' '[Peer]'
    printf '%s\n' 'Endpoint = 203.0.113.20:51820'
    printf '%s\n' 'AllowedIPs = 0.0.0.0/0'
} > "${brand_nokey}/config.conf"
detail_ok=1
if ! install_vpn_bundle openvpn cyberghost cg-wrap "${wrap_zip}"; then
    detail_ok=0
fi
grep -q 'auth-user-pass auth.txt' "${VPN_STAGE_DIR}/runtime" || detail_ok=0
grep -q 'redirect-gateway' "${VPN_STAGE_DIR}/runtime" && detail_ok=0
grep -q 'password.txt' "${VPN_STAGE_DIR}/runtime" && detail_ok=0
[[ -f "${VPN_STAGE_DIR}/ca.crt" && -f "${VPN_STAGE_DIR}/client.key" ]] || detail_ok=0
grep -q 'brand=cyberghost' "${VPN_STAGE_DIR}/meta" || detail_ok=0
[[ -d "${import_root}/vpn/openvpn/cg-wrap" ]] && detail_ok=0
if ! install_vpn_bundle openvpn cyberghost cg-root "${root_zip}"; then
    detail_ok=0
fi
grep -q 'auth-user-pass auth.txt' "${VPN_STAGE_DIR}/runtime" || detail_ok=0
[[ -d "${import_root}/vpn/openvpn/cg-root" ]] && detail_ok=0
: > "${vpn_fault_log}"
if ( install_vpn_bundle openvpn cyberghost cg-short "${short_zip}" ); then
    detail_ok=0
fi
grep -q 'vpn.import.auth 1' "${vpn_fault_log}" || detail_ok=0
[[ -d "${import_root}/vpn/openvpn/cg-short" ]] && detail_ok=0
: > "${vpn_fault_log}"
if ( install_vpn_bundle openvpn cyberghost cg-gone /no/such/vpn-archive.zip ); then
    detail_ok=0
fi
grep -q 'vpn.import.absent' "${vpn_fault_log}" || detail_ok=0
grep -q '/no/such/vpn-archive.zip' "${vpn_fault_log}" || detail_ok=0
: > "${vpn_fault_log}"
if ( install_vpn_bundle openvpn cyberghost cg-gap "${brand_gap}" ); then
    detail_ok=0
fi
grep -q 'vpn.import.lack' "${vpn_fault_log}" || detail_ok=0
grep -q 'client.key' "${vpn_fault_log}" || detail_ok=0
: > "${vpn_fault_log}"
if ( install_vpn_bundle openvpn cyberghost cg-extra "${brand_extra}" ); then
    detail_ok=0
fi
grep -q 'vpn.import.extra' "${vpn_fault_log}" || detail_ok=0
grep -q 'readme.txt' "${vpn_fault_log}" || detail_ok=0
: > "${vpn_fault_log}"
if ( install_vpn_bundle openvpn nordvpn nord-file "${brand_zip}" ); then
    detail_ok=0
fi
grep -q 'vpn.import.replace' "${vpn_fault_log}" || detail_ok=0
grep -q 'config.ovpn' "${vpn_fault_log}" || detail_ok=0
: > "${vpn_fault_log}"
if ( install_vpn_bundle wireguard mullvad mu-nokey "${brand_nokey}" ); then
    detail_ok=0
fi
grep -q 'vpn.import.missing' "${vpn_fault_log}" || detail_ok=0
grep -q 'PublicKey' "${vpn_fault_log}" || detail_ok=0
[[ -d "${import_root}/vpn/wireguard/mu-nokey" ]] && detail_ok=0
: > "${vpn_fault_log}"
if ( install_vpn_bundle openvpn cyberghost cg-two "${two_zip}" ); then
    detail_ok=0
fi
grep -q 'vpn.import.zipdir' "${vpn_fault_log}" || detail_ok=0
if [[ "${vpn_had_log_error}" -eq 1 ]]; then
    eval "$(declare -f vpn_saved_log_error | sed '1s/^vpn_saved_log_error/log_error/')"
    unset -f vpn_saved_log_error
else
    unset -f log_error
fi
if [[ "${detail_ok}" -eq 1 ]]; then
    t_pass "vpn.import.detail" "motif nommé, auth.txt adapté"
else
    t_fail "vpn.import.detail" "$(tr '\n' ' ' < "${vpn_fault_log}")"
fi

unset VPN_IMPORT_STAGE_ONLY
run_vpn_test() { return 1; }
roll_ok=1
if install_vpn_openvpn "cg-roll" "${brand_cg}/openvpn.ovpn"; then
    roll_ok=0
fi
[[ -d "${import_root}/vpn/openvpn/cg-roll" ]] && roll_ok=0
unset -f run_vpn_test
if [[ "${roll_ok}" -eq 1 ]]; then
    t_pass "vpn.rollback" "essai en échec, rien publié"
else
    t_fail "vpn.rollback" "profil publié"
fi
if [[ -n "${saved_import}" ]]; then
    export CONFIG_BASE_DIRECTORY="${saved_import}"
else
    unset CONFIG_BASE_DIRECTORY
fi

# shellcheck disable=SC1091
source "${vpn_dir}/failover.sh"
apply_vpn_systemd() { return 0; }
clear_vpn_network() { return 0; }
restart_vpn_services() { return 0; }
remove_vpn_iface() { return 0; }
arm_vpn_lockdown() { return 0; }
VPN_TRACE=""
send_vpn_alert() { VPN_TRACE="${VPN_TRACE}alert "; return 0; }
run_vpn_mode_off() {
    VPN_TRACE="${VPN_TRACE}off "
    set_vpn_state_mode off
    VPN_MODE=off
}
life_root="${ARTIFACTS}/vpn-life-root"
rm -rf "${life_root}"
mkdir -p "${life_root}"
export CONFIG_BASE_DIRECTORY="${life_root}"
life_ok=1
write_vpn_state || life_ok=0
if ( run_vpn_mode_on ); then
    life_ok=0
fi
load_vpn_settings
check_vpn_mode && life_ok=0
kept="${life_root}/vpn/openvpn/kept"
mkdir -p "${kept}"
printf 'proto=openvpn\n' > "${kept}/meta"
set_vpn_state_mode on
VPN_TRACE=""
run_vpn_mode_off
[[ -d "${kept}" ]] || life_ok=0
load_vpn_settings
check_vpn_mode && life_ok=0
rm -rf "${kept}"
solo="${life_root}/vpn/openvpn/solo"
mkdir -p "${solo}"
printf 'proto=openvpn\n' > "${solo}/meta"
set_vpn_state_mode on
forget_vpn_profile solo rm
[[ -d "${solo}" ]] && life_ok=0
load_vpn_settings
check_vpn_mode && life_ok=0
left="${life_root}/vpn/openvpn/left"
mkdir -p "${left}"
printf 'proto=openvpn\n' > "${left}/meta"
set_vpn_state_mode on
VPN_TRACE=""
run_vpn_failover
[[ -d "${left}" ]] || life_ok=0
load_vpn_settings
check_vpn_mode || life_ok=0
[[ "${VPN_TRACE}" == "alert " ]] || life_ok=0
rm -rf "${left}"
set_vpn_state_mode on
VPN_TRACE=""
run_vpn_failover
load_vpn_settings
check_vpn_mode && life_ok=0
[[ "${VPN_TRACE}" == "alert off " ]] || life_ok=0
if [[ -n "${saved_import}" ]]; then
    export CONFIG_BASE_DIRECTORY="${saved_import}"
else
    unset CONFIG_BASE_DIRECTORY
fi
if [[ "${life_ok}" -eq 1 ]]; then
    t_pass "vpn.life" "dernier retrait, mode, reprise"
else
    t_fail "vpn.life" "trace ${VPN_TRACE}"
fi
