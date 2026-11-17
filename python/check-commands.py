#!/usr/bin/env python3
# =============================================================================
# File       : python/check-commands.py
# Updated at : 2026-11-17
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Check the command table and the installation order.
# -----------------------------------------------------------------------------


import csv
import json
import re
import sys
from pathlib import Path

VERBS = (
    "configure",
    "check",
    "run",
    "lynis",
    "logs",
    "help",
    "vpn",
    "verify",
    "maintain",
    "timer",
    "cron",
    "install",
)
PATHS = (
    "scripts/bootstrap-workspace.sh",
    "scripts/publish-mirror.sh",
    "scripts/go-commit.sh",
    "scripts/vm-export-logs.sh",
    "scripts/vm-probe.sh",
    "agents/route.sh",
    "workstation/script/test/run.sh",
    "server/script/test/run.sh",
    "agents/search.sh",
    "scripts/render-install.sh",
    "scripts/list-names.sh",
)
ALLOWED = {"parent", "server", "workstation", "both"}


def read_rows(path):
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def row_fields(row):
    command = (row.get("command") or "").strip()
    product = (row.get("product") or "").strip()
    utility = (row.get("utility") or "").strip()
    return command, product, utility


def collect_commands(rows):
    seen = set()
    commands = []
    for row in rows:
        command, product, utility = row_fields(row)
        if not command or not utility or product not in ALLOWED:
            print(f"ligne refusée : {command}")
            sys.exit(1)
        key = (command, product)
        if key in seen:
            print(f"doublon : {product} {command}")
            sys.exit(1)
        seen.add(key)
        commands.append(command)
    return commands


# The formatter may insert a space before the bar.
def verb_arm(verb):
    if verb == "help":
        return ("help|", "help |")
    if verb in ("timer", "cron"):
        return ("timer|cron)", "timer | cron)")
    return (f"{verb})",)


def verb_ok(verb, blob, launch):
    arms = verb_arm(verb)
    if f"liltress {verb}" not in blob and f'liltress" {verb}' not in blob:
        print(f"verbe absent : {verb}")
        return False
    if arms[0] not in launch and arms[-1] not in launch:
        print(f"verbe hors de launch.sh : {verb}")
        return False
    return True


def require_verbs(blob, launch):
    for verb in VERBS:
        if not verb_ok(verb, blob, launch):
            sys.exit(1)


def require_paths(blob):
    for name in PATHS:
        if name not in blob:
            print(f"commande absente : {name}")
            sys.exit(1)


def check_csv(csv_path, launch_path):
    launch = Path(launch_path).read_text(encoding="utf-8")
    path = Path(csv_path)
    if not path.is_file():
        print("fichier absent")
        sys.exit(1)
    rows = read_rows(path)
    if not rows:
        print("aucune ligne")
        sys.exit(1)
    blob = "\n".join(collect_commands(rows))
    require_verbs(blob, launch)
    require_paths(blob)
    print("ok")


def plan_paths(root, product):
    relative = "config/schema/installation.json"
    data = json.loads((root / product / relative).read_text(encoding="utf-8"))
    order = []
    for category in data["categories"]:
        for step in category["steps"]:
            order.append(step.get("path") or step.get("action"))
    return order


def map_paths(text):
    lines = text.splitlines()
    start = None
    for cursor, line in enumerate(lines):
        if line.strip() == "| # | Script | Note |":
            start = cursor + 2
            break
    if start is None:
        print("tableau absent")
        sys.exit(1)
    paths = []
    for line in lines[start:]:
        if not line.startswith("|"):
            break
        found = re.search(r"`([^`]+)`", line)
        if not found:
            print("ligne sans script")
            sys.exit(1)
        paths.append(found.group(1))
    return paths


def report_order(code, listed):
    for number, pair in enumerate(zip(code, listed), 1):
        if pair[0] != pair[1]:
            print(f"{number} code={pair[0]} carte={pair[1]}")
            sys.exit(1)
    if len(code) > len(listed):
        print(f"carte courte {code[len(listed)]}")
    else:
        print(f"code court {listed[len(code)]}")
    sys.exit(1)


def same_order(root, product):
    code = plan_paths(root, product)
    listed = map_paths((root / "agents" / "maps" / f"{product}.md").read_text(encoding="utf-8"))
    if code == listed:
        return True
    print(f"{product} code={len(code)} carte={len(listed)}")
    report_order(code, listed)
    return False


def check_order(root):
    base = Path(root)
    for product in ("workstation", "server"):
        if not same_order(base, product):
            return
    print("ok")


def run_check_commands():
    mode = sys.argv[1]
    sys.argv = [sys.argv[0]] + sys.argv[2:]
    if mode == "csv":
        check_csv(sys.argv[1], sys.argv[2])
        return
    if mode == "order":
        check_order(sys.argv[1])
        return
    sys.exit("mode python refusé")


run_check_commands()
