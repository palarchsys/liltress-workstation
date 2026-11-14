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

cd_count="$(grep -c -- '--cd' "${vpn_dir}/up.sh" || true)"
ipv6_count="$(grep -c -- 'route-ipv6' "${vpn_dir}/up.sh" || true)"
if [[ "${cd_count}" -eq 1 ]]; then
    t_pass "vpn.cd" "la sonde garde --cd"
else
    t_fail "vpn.cd" "compte ${cd_count}"
fi
if [[ "${ipv6_count}" -eq 1 ]]; then
    t_pass "vpn.pull-filter" "la sonde ignore route-ipv6"
else
    t_fail "vpn.pull-filter" "compte ${ipv6_count}"
fi

# shellcheck disable=SC1091
source "${vpn_dir}/up.sh"
reason_root="${ARTIFACTS}/vpn-reason"
rm -rf "${reason_root}"
mkdir -p "${reason_root}/vpn/openvpn/cg-reason" "${reason_root}/vpn/openvpn/cg-auth" "${reason_root}/log/vpn"
printf '%s\n' "Options error: --ca fails with '/var/tmp/profile/ca.crt'" > "${reason_root}/vpn/openvpn/cg-reason/openvpn.log"
printf '%s\n' "AUTH_FAILED" > "${reason_root}/vpn/openvpn/cg-auth/openvpn.log"
saved_reason="${CONFIG_BASE_DIRECTORY:-}"
saved_install="${INSTALL_DIRECTORY:-}"
export CONFIG_BASE_DIRECTORY="${reason_root}"
export INSTALL_DIRECTORY="${reason_root}"
reason_log="${ARTIFACTS}/vpn-reason-msg.log"
: > "${reason_log}"
reason_had_info=0
if declare -F log_info >/dev/null 2>&1; then
    reason_had_info=1
    eval "$(declare -f log_info | sed '1s/^log_info/vpn_saved_log_info/')"
fi
log_info() {
    printf '%s\n' "$*" >> "${reason_log}"
    return 0
}
report_vpn_fail "cg-reason"
report_vpn_fail "cg-auth"
reason_ok=1
grep -q 'vpn.test.fail-reason cg-reason' "${reason_log}" || reason_ok=0
grep -q 'ca.crt' "${reason_log}" || reason_ok=0
grep -q '/var/tmp' "${reason_log}" && reason_ok=0
grep -q 'vpn.import.auth-failed cg-auth' "${reason_log}" || reason_ok=0
mkdir -p "${reason_root}/vpn/openvpn/cg-nmfail"
printf '%s\n' 'Initialization Sequence Completed' > "${reason_root}/vpn/openvpn/cg-nmfail/probe.log"
VPN_NM_FAULT="load"
report_vpn_fail "cg-nmfail"
nm_msg_ok=1
grep -q 'vpn.nm.fail cg-nmfail' "${reason_log}" || nm_msg_ok=0
grep -q 'vpn.test.fail cg-nmfail' "${reason_log}" && nm_msg_ok=0
unset VPN_NM_FAULT
if [[ "${reason_had_info}" -eq 1 ]]; then
    eval "$(declare -f vpn_saved_log_info | sed '1s/^vpn_saved_log_info/log_info/')"
    unset -f vpn_saved_log_info
else
    unset -f log_info
fi
if [[ -n "${saved_reason}" ]]; then
    export CONFIG_BASE_DIRECTORY="${saved_reason}"
else
    unset CONFIG_BASE_DIRECTORY
fi
if [[ -n "${saved_install}" ]]; then
    export INSTALL_DIRECTORY="${saved_install}"
else
    unset INSTALL_DIRECTORY
fi
if [[ "${reason_ok}" -eq 1 ]]; then
    t_pass "vpn.fail-reason" "motif OpenVPN, sans chemin absolu"
    t_pass "vpn.auth-failed" "identifiant refusé"
else
    t_fail "vpn.fail-reason" "$(tr '\n' ' ' < "${reason_log}")"
    t_fail "vpn.auth-failed" "$(tr '\n' ' ' < "${reason_log}")"
fi
if [[ "${nm_msg_ok}" -eq 1 ]]; then
    t_pass "vpn.nm.fail" "refus NetworkManager, poignée de main réussie"
else
    t_fail "vpn.nm.fail" "$(tr '\n' ' ' < "${reason_log}")"
fi

day_root="${ARTIFACTS}/vpn-day"
rm -rf "${day_root}"
mkdir -p "${day_root}"
export INSTALL_DIRECTORY="${day_root}"
note_vpn_log import "cg-day" ok "openvpn 203.0.113.10"
note_vpn_log test "cg-day" fail "Options error: --ca fails with ca.crt"
note_vpn_log watch "cg-day" ok "up"
day_file="${day_root}/log/vpn/$(date '+%Y-%m-%d').log"
day_ok=1
[[ -f "${day_file}" ]] || day_ok=0
[[ "$(wc -l < "${day_file}" | tr -d ' ')" == "2" ]] || day_ok=0
[[ "$(stat -c '%a' "${day_file}")" == "600" ]] || day_ok=0
[[ "$(stat -c '%a' "${day_root}/log/vpn")" == "700" ]] || day_ok=0
grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{9}[+-][0-9]{4}' "${day_file}" || day_ok=0
grep -q 'import' "${day_file}" || day_ok=0
grep -q 'test' "${day_file}" || day_ok=0
note_vpn_log import "cg-day" fail "BEGIN PRIVATE KEY abcdef"
grep -q 'PRIVATE' "${day_file}" && day_ok=0
grep -q 'BEGIN' "${day_file}" && day_ok=0
grep -q 'auth.txt' "${day_file}" && day_ok=0
if [[ -n "${saved_install}" ]]; then
    export INSTALL_DIRECTORY="${saved_install}"
else
    unset INSTALL_DIRECTORY
fi
if [[ "${day_ok}" -eq 1 ]]; then
    t_pass "vpn.day-log" "un fichier par jour, horodaté"
else
    t_fail "vpn.day-log" "$(tr '\n' ' ' < "${day_file}" 2>/dev/null)"
fi

# shellcheck disable=SC1091
source "${vpn_dir}/routes.sh"
ensure_vpn_table() { return 0; }
iface_root="${ARTIFACTS}/vpn-iface"
rm -rf "${iface_root}"
mkdir -p "${iface_root}/vpn/openvpn/cg-tun/bin"
printf 'proto=openvpn\niface=tun-liltress\nhas_ipv6=0\n' > "${iface_root}/vpn/openvpn/cg-tun/meta"
cat > "${iface_root}/vpn/openvpn/cg-tun/bin/ip" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${VPN_IP_LOG}"
case "$1" in
    link)
        if [[ -f "${VPN_IP_READY}" ]]; then
            exit 0
        fi
        if [[ "${VPN_IP_ARM:-}" == "1" ]]; then
            touch "${VPN_IP_READY}"
        fi
        printf '%s\n' 'Cannot find device "tun-liltress"' >&2
        exit 1
        ;;
    rule)
        [[ "$2" == "del" ]] && exit 1
        exit 0
        ;;
    route)
        if [[ "$2" == "replace" && ! -f "${VPN_IP_READY}" ]]; then
            printf '%s\n' 'Cannot find device "tun-liltress"' >&2
            exit 1
        fi
        exit 0
        ;;
esac
exit 0
EOF
chmod 700 "${iface_root}/vpn/openvpn/cg-tun/bin/ip"
saved_iface_base="${CONFIG_BASE_DIRECTORY:-}"
saved_iface_path="${PATH}"
export CONFIG_BASE_DIRECTORY="${iface_root}"
export VPN_IP_LOG="${iface_root}/ip.log"
export VPN_IP_READY="${iface_root}/ready"
unset VPN_IP_ARM
: > "${VPN_IP_LOG}"
export PATH="${iface_root}/vpn/openvpn/cg-tun/bin:${PATH}"
iface_err="${iface_root}/miss.err"
: > "${iface_err}"
iface_ok=1
if apply_vpn_tunnel_routes cg-tun >/dev/null 2>"${iface_err}"; then
    :
else
    iface_ok=0
fi
[[ ! -s "${iface_err}" ]] || iface_ok=0
grep -q 'route replace' "${VPN_IP_LOG}" && iface_ok=0
rm -f "${VPN_IP_READY}"
: > "${VPN_IP_LOG}"
: > "${iface_err}"
export VPN_IP_ARM=1
if wait_vpn_iface cg-tun >/dev/null 2>"${iface_err}"; then
    :
else
    iface_ok=0
fi
[[ ! -s "${iface_err}" ]] || iface_ok=0
if apply_vpn_tunnel_routes cg-tun >/dev/null 2>>"${iface_err}"; then
    :
else
    iface_ok=0
fi
[[ ! -s "${iface_err}" ]] || iface_ok=0
grep -q 'route replace' "${VPN_IP_LOG}" && iface_ok=0
if awk '
    /^run_vpn_profile\(\)/ { inside=1 }
    inside && /^}/ { exit }
    inside && /openvpn/ { bad=1 }
    inside && /route replace/ { bad=1 }
    inside && /apply_vpn_profile/ { seen=1 }
    END { if (seen && !bad) exit 0; exit 1 }
' "${vpn_dir}/failover.sh"; then
    :
else
    iface_ok=0
fi
grep -q 'wait_vpn_iface' "${vpn_dir}/up.sh" || iface_ok=0
export PATH="${saved_iface_path}"
unset VPN_IP_LOG VPN_IP_READY VPN_IP_ARM
if [[ -n "${saved_iface_base}" ]]; then
    export CONFIG_BASE_DIRECTORY="${saved_iface_base}"
else
    unset CONFIG_BASE_DIRECTORY
fi
if [[ "${iface_ok}" -eq 1 ]]; then
    t_pass "vpn.iface" "route après l'interface, sans texte ip"
else
    t_fail "vpn.iface" "$(tr '\n' ' ' < "${iface_err}") $(tr '\n' ' ' < "${iface_root}/ip.log")"
fi

# shellcheck disable=SC1091
source "${vpn_dir}/nm.sh"
nm_root="${ARTIFACTS}/vpn-nm"
rm -rf "${nm_root}"
mkdir -p "${nm_root}/vpn/openvpn/cg-nm" "${nm_root}/vpn/wireguard/cg-wg" "${nm_root}/bin"
saved_nm_base="${CONFIG_BASE_DIRECTORY:-}"
saved_nm_path="${PATH}"
saved_nm_install="${INSTALL_DIRECTORY:-}"
export CONFIG_BASE_DIRECTORY="${nm_root}"
export VPN_NM_DIR="${nm_root}/nm"
export INSTALL_DIRECTORY="${nm_root}"
nm_ok=1
nm_why=""
cat > "${nm_root}/vpn/openvpn/cg-nm/runtime" << 'EOF'
remote 203.0.113.10 1194 udp
proto udp
ca ca.crt
cert client.crt
key client.key
auth-user-pass auth.txt
dev tun-liltress
remote-cert-tls server
EOF
cat > "${nm_root}/vpn/openvpn/cg-nm/meta" << 'EOF'
proto=openvpn
endpoint4=203.0.113.10
port=1194
transport=udp
iface=tun-liltress
has_ipv6=0
encrypted=0
brand=cyberghost
EOF
printf '%s\n' 'user-one' 's3cret-line' > "${nm_root}/vpn/openvpn/cg-nm/auth.txt"
nm_out="${nm_root}/stdout"
nm_err="${nm_root}/stderr"
if install_vpn_nm_connection cg-nm > "${nm_out}" 2> "${nm_err}"; then
    :
else
    nm_ok=0
    nm_why="install"
fi
nm_file="${VPN_NM_DIR}/liltress-cg-nm.nmconnection"
nm_ca="$(get_vpn_profile_dir cg-nm)/ca.crt"
[[ -f "${nm_file}" ]] || { nm_ok=0; nm_why="fichier"; }
if [[ -f "${nm_file}" ]]; then
    grep -q '^id=cg-nm$' "${nm_file}" || { nm_ok=0; nm_why="id"; }
    grep -q '^interface-name=tun-liltress$' "${nm_file}" || { nm_ok=0; nm_why="iface"; }
    grep -q '^ignore-auto-dns=true$' "${nm_file}" || { nm_ok=0; nm_why="dns"; }
    grep -F -q "ca=${nm_ca}" "${nm_file}" || { nm_ok=0; nm_why="ca"; }
    grep -q '^username=user-one$' "${nm_file}" || { nm_ok=0; nm_why="user"; }
    grep -q '^password-flags=0$' "${nm_file}" || { nm_ok=0; nm_why="flags"; }
    grep -qx 'liltress.profile=cg-nm' "${nm_file}" || { nm_ok=0; nm_why="marque"; }
    grep -q '^data=' "${nm_file}" && { nm_ok=0; nm_why="data"; }
    [[ "$(vpn_nm_profile_mark "${nm_file}")" == "cg-nm" ]] || { nm_ok=0; nm_why="lecture"; }
    [[ "$(stat -c '%a' "${nm_file}")" == "600" ]] || { nm_ok=0; nm_why="mode"; }
fi
grep -q 's3cret-line' "${nm_out}" && { nm_ok=0; nm_why="stdout"; }
grep -q 's3cret-line' "${nm_err}" && { nm_ok=0; nm_why="stderr"; }
wg_mark="$(printf '%s%s' 'Private' 'Key')"
{
    printf '[Interface]\n'
    printf '%s = abcdef\n' "${wg_mark}"
    printf '%s\n' 'Address = 10.64.0.2/32'
    printf '%s\n' '[Peer]'
    printf '%s\n' 'PublicKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB='
    printf '%s\n' 'Endpoint = 203.0.113.10:51820'
} > "${nm_root}/vpn/wireguard/cg-wg/runtime"
cat > "${nm_root}/vpn/wireguard/cg-wg/meta" << 'EOF'
proto=wireguard
endpoint4=203.0.113.10
port=51820
transport=udp
iface=wg-liltress
has_ipv6=0
encrypted=0
brand=mullvad
EOF
if install_vpn_nm_connection cg-wg > "${nm_out}" 2> "${nm_err}"; then
    :
else
    nm_ok=0
    nm_why="wg"
fi
wg_file="${VPN_NM_DIR}/liltress-cg-wg.nmconnection"
wg_needle="$(printf '%s%s =' 'Private' 'Key')"
if [[ -f "${wg_file}" ]]; then
    grep -q '^private-key=' "${wg_file}" || { nm_ok=0; nm_why="wg-key"; }
    grep -F -q "${wg_needle}" "${wg_file}" && { nm_ok=0; nm_why="aiguille"; }
    grep -q '^interface-name=wg-liltress$' "${wg_file}" || { nm_ok=0; nm_why="wg-iface"; }
    grep -qx 'liltress.profile=cg-wg' "${wg_file}" || { nm_ok=0; nm_why="wg-marque"; }
    grep -q '^data=' "${wg_file}" && { nm_ok=0; nm_why="wg-data"; }
else
    nm_ok=0
    nm_why="wg-fichier"
fi
grep -q 'abcdef' "${nm_out}" && { nm_ok=0; nm_why="wg-stdout"; }
rm -f "${nm_root}/vpn/direct.ok"
[[ "$(vpn_route_lookup)" == "main" ]] || { nm_ok=0; nm_why="lookup-main"; }
printf '1\n' > "${nm_root}/vpn/direct.ok"
[[ "$(vpn_route_lookup)" == "w_direct" ]] || { nm_ok=0; nm_why="lookup-direct"; }
cat > "${nm_root}/bin/ip" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${NM_IP_LOG}"
if [[ "$1" == "-4" || "$1" == "-6" ]] && [[ "$2" == "rule" && "$3" == "del" ]]; then
    exit 1
fi
if [[ "$1" == "rule" && "$2" == "del" ]]; then
    exit 1
fi
exit 0
EOF
chmod 700 "${nm_root}/bin/ip"
export NM_IP_LOG="${nm_root}/ip.log"
: > "${NM_IP_LOG}"
export PATH="${nm_root}/bin:${PATH}"
if apply_vpn_ssh >/dev/null 2>> "${nm_err}"; then
    :
else
    nm_ok=0
    nm_why="ssh"
fi
grep -q 'lookup w_direct' "${NM_IP_LOG}" || { nm_ok=0; nm_why="ssh-table"; }
grep -q 'priority 45' "${NM_IP_LOG}" || { nm_ok=0; nm_why="ssh-prio"; }
grep -qx -- '-4 rule del priority 45' "${NM_IP_LOG}" || { nm_ok=0; nm_why="del4"; }
grep -qx -- '-6 rule del priority 45' "${NM_IP_LOG}" || { nm_ok=0; nm_why="del6"; }
export PATH="${saved_nm_path}"
write_vpn_state || { nm_ok=0; nm_why="etat"; }
set_vpn_state_mode on || { nm_ok=0; nm_why="mode-on"; }
NM_TRACE=""
for nm_fn in set_vpn_state_mode clear_vpn_tunnel_routes set_vpn_state_active record_vpn_attempt apply_vpn_nft restart_vpn_services apply_vpn_systemd apply_vpn_endpoint_routes apply_vpn_bypass_routes apply_vpn_ssh remember_vpn_direct_route; do
    if declare -F "${nm_fn}" >/dev/null 2>&1; then
        eval "$(declare -f "${nm_fn}" | sed "1s/^${nm_fn}/nm_saved_${nm_fn}/")"
    fi
done
set_vpn_state_mode() {
    NM_TRACE="${NM_TRACE}${1} "
    return 0
}
clear_vpn_tunnel_routes() { return 0; }
set_vpn_state_active() { return 0; }
record_vpn_attempt() { return 0; }
apply_vpn_nft() { return 0; }
restart_vpn_services() { return 0; }
apply_vpn_systemd() { return 0; }
apply_vpn_endpoint_routes() { return 0; }
apply_vpn_bypass_routes() { return 0; }
apply_vpn_ssh() { return 0; }
NM_REMEMBER=0
remember_vpn_direct_route() {
    NM_REMEMBER=1
    return 0
}
unset CONNECTION_FILENAME
NM_TRACE=""
handle_vpn_nm_event eth0 vpn-up
[[ -z "${NM_TRACE}" ]] || { nm_ok=0; nm_why="sans-marque"; }
printf '%s\n' '[connection]' 'id=other' > "${VPN_NM_DIR}/other.nmconnection"
export CONNECTION_FILENAME="${VPN_NM_DIR}/other.nmconnection"
NM_TRACE=""
handle_vpn_nm_event eth0 vpn-up
[[ -z "${NM_TRACE}" ]] || { nm_ok=0; nm_why="etranger"; }
export CONNECTION_FILENAME="${nm_file}"
vpn_nm_hold_on
NM_TRACE=""
handle_vpn_nm_event tun-liltress vpn-up
[[ -z "${NM_TRACE}" ]] || { nm_ok=0; nm_why="retenu"; }
vpn_nm_hold_off
NM_TRACE=""
handle_vpn_nm_event tun-liltress vpn-up
[[ "${NM_TRACE}" == *"on"* ]] || { nm_ok=0; nm_why="mode"; }
NM_REMEMBER=0
handle_vpn_nm_event eth0 dhcp4-change
[[ "${NM_REMEMBER}" == "1" ]] || { nm_ok=0; nm_why="dhcp"; }
NM_REMEMBER=0
handle_vpn_nm_event tun-liltress dhcp4-change
[[ "${NM_REMEMBER}" == "0" ]] || { nm_ok=0; nm_why="dhcp-tun"; }
grep -q 'network-manager-openvpn-gnome' "${vpn_dir}/install.sh" || { nm_ok=0; nm_why="paquet"; }
for nm_fn in set_vpn_state_mode clear_vpn_tunnel_routes set_vpn_state_active record_vpn_attempt apply_vpn_nft restart_vpn_services apply_vpn_systemd apply_vpn_endpoint_routes apply_vpn_bypass_routes apply_vpn_ssh remember_vpn_direct_route; do
    if declare -F "nm_saved_${nm_fn}" >/dev/null 2>&1; then
        eval "$(declare -f "nm_saved_${nm_fn}" | sed "1s/^nm_saved_${nm_fn}/${nm_fn}/")"
        unset -f "nm_saved_${nm_fn}"
    fi
done
unset -v nm_fn
export PATH="${saved_nm_path}"
if [[ -n "${saved_nm_base}" ]]; then
    export CONFIG_BASE_DIRECTORY="${saved_nm_base}"
else
    unset CONFIG_BASE_DIRECTORY
fi
if [[ -n "${saved_nm_install}" ]]; then
    export INSTALL_DIRECTORY="${saved_nm_install}"
else
    unset INSTALL_DIRECTORY
fi
unset VPN_NM_DIR CONNECTION_FILENAME NM_TRACE NM_REMEMBER NM_IP_LOG
if [[ "${nm_ok}" -eq 1 ]]; then
    t_pass "vpn.nm" "fiche NetworkManager, table directe, répartiteur"
else
    t_fail "vpn.nm" "${nm_why}"
fi
