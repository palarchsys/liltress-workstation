#!/usr/bin/env bash
# =============================================================================
# File       : test/suites/07_router.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

t_section "routeur"
root=""
here="${T_ROOT}"
while [[ "${here}" != "/" ]]; do
    if [[ -f "${here}/agents/route.sh" ]]; then
        root="${here}"
        break
    fi
    here="$(dirname -- "${here}")"
done

if [[ -z "${root}" ]]; then
    t_fail "route.check" "agents/route.sh introuvable au-dessus de ${T_ROOT}"
elif bash "${root}/agents/route.sh" --check > "${G_ARTIFACTS}/route.txt"; then
    t_pass "route.check" "fichiers cités présents"
else
    t_fail "route.check" "$(tr '\n' ' ' < "${G_ARTIFACTS}/route.txt")"
fi

if [[ -n "${root}" ]] && python3 - "${root}/agents/maps/commands.csv" "${root}/core/launch.sh" > "${G_ARTIFACTS}/commands.txt" 2>&1 << 'PY'
import csv
import sys
from pathlib import Path

csv_path = Path(sys.argv[1])
launch = Path(sys.argv[2]).read_text(encoding="utf-8")
if not csv_path.is_file():
    print("fichier absent")
    sys.exit(1)
with csv_path.open(encoding="utf-8", newline="") as handle:
    rows = list(csv.DictReader(handle))
if not rows:
    print("aucune ligne")
    sys.exit(1)
allowed = {"parent", "server", "workstation", "both"}
seen = set()
commands = []
for row in rows:
    command = (row.get("command") or "").strip()
    product = (row.get("product") or "").strip()
    utility = (row.get("utility") or "").strip()
    if not command or not utility or product not in allowed:
        print(f"ligne refusée : {command}")
        sys.exit(1)
    key = (command, product)
    if key in seen:
        print(f"doublon : {product} {command}")
        sys.exit(1)
    seen.add(key)
    commands.append(command)
blob = "\n".join(commands)
for verb in ("configure", "check", "run", "lynis", "logs", "help"):
    if f"liltress {verb}" not in blob:
        print(f"verbe absent : {verb}")
        sys.exit(1)
    arm = "help|" if verb == "help" else f"{verb})"
    if arm not in launch:
        print(f"verbe hors de launch.sh : {verb}")
        sys.exit(1)
for name in (
    "scripts/bootstrap-workspace.sh",
    "scripts/publish-mirror.sh",
    "scripts/vm-export-logs.sh",
    "scripts/vm-probe.sh",
    "agents/route.sh",
    "verify/alerts.sh",
    "verify/workstation.sh",
    "verify/boot.sh",
    "verify/chkrootkit-fp.sh",
    "scan-skip.sh",
    "verify/matrix.sh",
    "verify/livekit.sh",
    "verify/wireguard.sh",
    "workstation/test/run.sh",
    "server/test/run.sh",
    "agents/search.sh",
    "scripts/render-install.sh",
    "scripts/list-names.sh",
):
    if name not in blob:
        print(f"commande absente : {name}")
        sys.exit(1)
print("ok")
PY
then
    t_pass "commands.csv" "liste alignée sur les commandes"
else
    t_fail "commands.csv" "$(tr '\n' ' ' < "${G_ARTIFACTS}/commands.txt" 2>/dev/null || true)"
fi

if [[ -n "${root}" ]]; then
    t_check_route() {
        local id="$1"
        local query="$2"
        local expect="$3"
        local got
        got="$(bash "${root}/agents/route.sh" "${query}")"
        if [[ "${got}" == "${expect}" ]]; then
            t_pass "route.${id}" "${query}"
        else
            t_fail "route.${id}" "${got}"
        fi
    }

    t_check_route history "historique version antérieure" $'agents/laws/history.md\nagents/laws/style.md'
    t_check_route tests "test" "agents/maps/tests.md"
    t_check_route probe "anomalie sonde" $'agents/laws/logs.md\nagents/maps/probe.md'
    t_check_route install "installeur" $'agents/laws/install.md\nagents/maps/core.md'
    t_check_route git.gitignore "gitignore" "agents/laws/git.md"
    t_check_route names.inventaire "inventaire des noms" $'agents/laws/names.md\nagents/maps/names.md'
    t_check_route names.keep-variable "variable" "agents/laws/naming.md"
    t_check_route compat.postfix "compatibilité postfix" $'agents/laws/compat.md\nagents/maps/versions.md'
    t_check_route compat.sasl "sasl 26.10" $'agents/laws/compat.md\nagents/maps/versions.md'
    t_check_route compat.esm "esm-infra" $'agents/laws/compat.md\nagents/maps/versions.md'

    help_user="$(bash "${root}/workstation/liltress" help)"
    help_server="$(bash "${root}/server/liltress" help)"
    if [[ "${help_user}" == *"verify/workstation.sh"* && "${help_user}" == *"/opt/liltress-workstation/bin/scan-skip.sh"* && "${help_user}" != *"--basic"* ]]; then
        t_pass "help.user" "commandes du poste"
    else
        t_fail "help.user" "écran poste incomplet"
    fi
    if [[ "${help_server}" == *"--basic"* && "${help_server}" == *"--avance"* && "${help_server}" == *"verify/matrix.sh"* && "${help_server}" != *"scan-skip"* ]]; then
        t_pass "help.server" "commandes du serveur"
    else
        t_fail "help.server" "écran serveur incomplet"
    fi

    if python3 - "${root}" > "${G_ARTIFACTS}/order.txt" 2>&1 << 'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])

def scripts_from_run(text):
    lines = text.splitlines()
    arrays = {}
    cases = {}
    index = 0
    while index < len(lines):
        stripped = lines[index].strip()
        if re.match(r"^STEP_[A-Z0-9_]+=\(", stripped):
            body = lines[index]
            while ")" not in body.split("#", 1)[0]:
                index += 1
                body += "\n" + lines[index]
            name = re.match(r"^STEP_[A-Z0-9_]+", stripped).group(0)
            arrays[name] = re.findall(r'"([^"]+\.sh)"', body)
            index += 1
            continue
        for var, path in re.findall(r'([A-Z][A-Z0-9_]*)="([^"]+\.sh)"', lines[index]):
            if not var.startswith("STEP_"):
                cases.setdefault(var, []).append(path)
        index += 1
    order = []
    token = re.compile(r'\$\{([A-Za-z0-9_]+)\[@\]\}|\$\{([A-Za-z0-9_]+)\}|"([^"]+\.sh)"')
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if "run_step" not in line and "system/purge.sh" in line and "bash " in line:
            order.append("system/purge.sh")
            continue
        if "run_step" not in line:
            continue
        for array_name, var_name, literal in token.findall(line):
            if literal and not literal.startswith("$"):
                order.append(literal)
            elif array_name:
                order.extend(arrays[array_name])
            elif var_name in ("G_INSTALL_DIRECTORY", "S_SERVER_TYPE"):
                continue
            elif var_name in cases:
                order.extend(cases[var_name])
            else:
                print(f"jeton inconnu {var_name}")
                sys.exit(1)
    return order

def map_paths(text):
    lines = text.splitlines()
    start = None
    for index, line in enumerate(lines):
        if line.strip() == "| # | Script | Note |":
            start = index + 2
            break
    if start is None:
        print("tableau absent")
        sys.exit(1)
    paths = []
    for line in lines[start:]:
        if not line.startswith("|"):
            break
        found = re.search(r"`([^`]+\.sh)`", line)
        if not found:
            print("ligne sans script")
            sys.exit(1)
        paths.append(found.group(1))
    return paths

for product in ("workstation", "server"):
    code = scripts_from_run((root / product / "scripts" / "run.sh").read_text(encoding="utf-8"))
    listed = map_paths((root / "agents" / "maps" / f"{product}.md").read_text(encoding="utf-8"))
    if code == listed:
        continue
    print(f"{product} code={len(code)} carte={len(listed)}")
    for number, pair in enumerate(zip(code, listed), 1):
        if pair[0] != pair[1]:
            print(f"{number} code={pair[0]} carte={pair[1]}")
            sys.exit(1)
    if len(code) > len(listed):
        print(f"carte courte {code[len(listed)]}")
    else:
        print(f"code court {listed[len(code)]}")
    sys.exit(1)
print("ok")
PY
    then
        t_pass "order.maps" "tableaux alignés sur run.sh"
    else
        t_fail "order.maps" "$(tr '\n' ' ' < "${G_ARTIFACTS}/order.txt" 2>/dev/null || true)"
    fi

    if bash "${root}/scripts/render-install.sh" --print workstation | cmp -s - "${root}/workstation/install.sh" \
        && bash "${root}/scripts/render-install.sh" --print server | cmp -s - "${root}/server/install.sh" \
        && bash "${root}/scripts/render-install.sh" --print workstation | grep -q 'liltress-workstation' \
        && bash "${root}/scripts/render-install.sh" --print workstation | grep -q 'scan-skip.paths' \
        && bash "${root}/scripts/render-install.sh" --print server | grep -q 'liltress-server' \
        && ! bash "${root}/scripts/render-install.sh" --print server | grep -q 'scan-skip.paths'
    then
        t_pass "install.template" "rendu égal aux deux install.sh"
    else
        t_fail "install.template" "le rendu diffère du fichier"
    fi

    if bash "${root}/agents/search.sh" render_install | grep -q 'scripts/render-install.sh'; then
        t_pass "search.hit" "motif trouvé"
    else
        t_fail "search.hit" "render-install.sh absent du résultat"
    fi
    status=0
    bash "${root}/agents/search.sh" >/dev/null 2>&1 || status=$?
    if [[ "${status}" -eq 2 ]]; then
        t_pass "search.usage" "sans motif, code 2"
    else
        t_fail "search.usage" "code ${status}"
    fi
    scope="$(bash "${root}/agents/search.sh" gold_gaming_trophy.png || true)"
    if [[ "${scope}" == *next_step* ]]; then
        t_fail "search.scope" "next_step est dans le résultat"
    else
        t_pass "search.scope" "next_step hors recherche"
    fi
fi
