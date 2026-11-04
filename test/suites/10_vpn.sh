#!/usr/bin/env bash
# =============================================================================
# File       : test/suites/10_vpn.sh
# Updated at : 2026-11-04
# Creator    : palarchsys
# =============================================================================

t_section "vpn"

vpn_dir="${T_ROOT}/service/vpn"
cfg_dir="${T_ROOT}/config/vpn"

while IFS= read -r file; do
    rel="${file#"${T_ROOT}/"}"
    if bash -n "${file}" 2>"${G_ARTIFACTS}/vpn-bash-n.err"; then
        t_pass "vpn.syntax:${rel}" "bash -n"
    else
        t_fail "vpn.syntax:${rel}" "$(tr '\n' ' ' < "${G_ARTIFACTS}/vpn-bash-n.err")"
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

if grep -q 'vpn)' "${T_ROOT}/core/launch.sh"; then
    t_pass "vpn.launch" "branche présente"
else
    t_fail "vpn.launch" "branche absente"
fi

if python3 - "${T_ROOT}/script/install.json" > "${G_ARTIFACTS}/vpn-order.txt" 2>&1 << 'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
paths = []
for category in data["categories"]:
    if category["id"] != "install.security.title":
        continue
    for step in category["steps"]:
        paths.append(step["path"])
unbound = paths.index("service/unbound/install.sh")
vpn = paths.index("service/vpn/install.sh")
apparmor = paths.index("service/apparmor/install.sh")
ufw = paths.index("service/ufw/configure.sh")
configure = paths.index("service/vpn/configure.sh")
usb = paths.index("service/usbguard/configure.sh")
if vpn != unbound + 1 or apparmor != vpn + 1:
    sys.exit("install hors place")
if configure != ufw + 1 or usb != configure + 1:
    sys.exit("configure hors place")
PY
then
    t_pass "vpn.order" "install.json"
else
    t_fail "vpn.order" "$(tr '\n' ' ' < "${G_ARTIFACTS}/vpn-order.txt")"
fi

forbid_phrase="$(printf '%s%s%s%s' 'ufw ' 'default ' 'deny ' 'outgoing')"
if grep -RInE -- "wg-quick|${forbid_phrase}|disable_ipv6|resolvconf" "${vpn_dir}" "${cfg_dir}" > "${G_ARTIFACTS}/vpn-forbid.txt"; then
    t_fail "vpn.forbid" "$(tr '\n' ' ' < "${G_ARTIFACTS}/vpn-forbid.txt" | head -c 400)"
else
    t_pass "vpn.forbid" "mots absents"
fi

if python3 - "${cfg_dir}/vpn.conf" "${T_ROOT}/service/ufw/egress.sh" "${vpn_dir}/lib.sh" > "${G_ARTIFACTS}/vpn-prio.txt" 2>&1 << 'PY'
import re
import sys
from pathlib import Path

conf = Path(sys.argv[1]).read_text(encoding="utf-8")
egress = Path(sys.argv[2]).read_text(encoding="utf-8")
lib = Path(sys.argv[3]).read_text(encoding="utf-8")
found = re.search(r"^W_VPN_FW_PRIORITY=(-?\d+)\s*$", conf, re.M)
if not found or found.group(1) != "-150":
    sys.exit("priorité absente")
if not re.search(r"priority 0", egress):
    sys.exit("priorité egress absente")
if "-150" not in lib:
    sys.exit("priorité absente du script")
if int(found.group(1)) >= 0:
    sys.exit("priorité non négative")
PY
then
    t_pass "vpn.priority" "-150"
else
    t_fail "vpn.priority" "$(tr '\n' ' ' < "${G_ARTIFACTS}/vpn-prio.txt")"
fi

if grep -RIn 'ct state established,related accept' "${vpn_dir}" "${cfg_dir}" > "${G_ARTIFACTS}/vpn-ct.txt"; then
    t_fail "vpn.ct" "$(tr '\n' ' ' < "${G_ARTIFACTS}/vpn-ct.txt" | head -c 400)"
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
parse_dir="${G_ARTIFACTS}/vpn-parse"
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
printf '[Interface]\n%s not-a-real-secret\n' "${marker}" > "${G_ARTIFACTS}/fake-wg.conf"
printf 'remote example.invalid 1194 udp\nca ca.crt\n' > "${G_ARTIFACTS}/fake.ovpn"
needle="$(printf '%s%s =' 'Private' 'Key')"
if git -C "${T_ROOT}" grep -n -F -e "${needle}" -- . ':!test/output' > "${G_ARTIFACTS}/vpn-secret-grep.txt" 2>/dev/null; then
    t_fail "vpn.secret-grep" "$(tr '\n' ' ' < "${G_ARTIFACTS}/vpn-secret-grep.txt" | head -c 300)"
else
    t_pass "vpn.secret-grep" "chaîne absente du suivi"
fi
if git -C "${T_ROOT}" ls-files | grep -E '(^|/)profiles/' > "${G_ARTIFACTS}/vpn-profiles.txt"; then
    t_fail "vpn.profiles" "$(tr '\n' ' ' < "${G_ARTIFACTS}/vpn-profiles.txt")"
else
    t_pass "vpn.profiles" "aucun profil versionné"
fi

if python3 - "${T_ROOT}/../core/text" "${T_ROOT}/locale" > "${G_ARTIFACTS}/vpn-keys.txt" 2>&1 << 'PY'
import re
import sys
from pathlib import Path

key_re = re.compile(r"^\[(vpn\.[a-z0-9-]+(?:\.[a-z0-9-]+)*)\]$")

def bag(root, lang):
    found = set()
    folder = Path(root) / lang
    for path in folder.glob("*.txt"):
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            match = key_re.match(line)
            if match and match.group(1).startswith("vpn."):
                found.add(match.group(1))
    return found

core = Path(sys.argv[1])
locale = Path(sys.argv[2])
base = bag(core, "en")
if not base:
    sys.exit("aucune clé")
for tree in (core, locale):
    for lang in ("en", "fr", "de", "es"):
        found = bag(tree, lang)
        if found != base:
            sys.exit(f"{tree} {lang} missing={sorted(base-found)[:6]} extra={sorted(found-base)[:6]}")
PY
then
    t_pass "vpn.keys" "quatre langues, deux arbres"
else
    t_fail "vpn.keys" "$(tr '\n' ' ' < "${G_ARTIFACTS}/vpn-keys.txt")"
fi
