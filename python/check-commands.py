#!/usr/bin/env python3
# =============================================================================
# File       : python/check-commands.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import sys

mode = sys.argv[1]
sys.argv = [sys.argv[0]] + sys.argv[2:]

if mode == 'csv':
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
    for verb in ("configure", "check", "run", "lynis", "logs", "help", "vpn"):
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
        "script/verify/alerts.sh",
        "script/verify/workstation.sh",
        "script/verify/boot.sh",
        "script/verify/chkrootkit-fp.sh",
        "scan-skip.sh",
        "script/verify/matrix.sh",
        "script/verify/livekit.sh",
        "script/verify/wireguard.sh",
        "workstation/script/test/run.sh",
        "server/script/test/run.sh",
        "agents/search.sh",
        "scripts/render-install.sh",
        "scripts/list-names.sh",
    ):
        if name not in blob:
            print(f"commande absente : {name}")
            sys.exit(1)
    print("ok")
elif mode == 'order':
    import json
    import re
    import sys
    from pathlib import Path

    root = Path(sys.argv[1])

    def plan_paths(product):
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
            found = re.search(r"`([^`]+)`", line)
            if not found:
                print("ligne sans script")
                sys.exit(1)
            paths.append(found.group(1))
        return paths

    for product in ("workstation", "server"):
        code = plan_paths(product)
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
else:
    sys.exit('mode python refusé')
