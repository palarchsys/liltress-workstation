#!/usr/bin/env python3
# =============================================================================
# File       : python/install-render.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import pathlib
import sys

template_path, product, dest = sys.argv[1:]
repos = {
    "workstation": "liltress-workstation",
    "server": "liltress-server",
}
if product not in repos:
    print(f"produit refusé : {product}", file=sys.stderr)
    sys.exit(1)

raw = pathlib.Path(template_path).read_text(encoding="utf-8").splitlines(keepends=True)
start = None
end = None
for index, line in enumerate(raw):
    if line.startswith("cat << 'END_TEMPLATE'"):
        start = index + 1
    elif start is not None and line.rstrip("\n") == "END_TEMPLATE":
        end = index
        break
if start is None or end is None:
    print("modèle illisible", file=sys.stderr)
    sys.exit(1)
text = "".join(raw[start:end])
token = "__HF_TEMPLATE_REPO__"
if text.count(token) != 1:
    print("jeton de dépôt absent ou répété", file=sys.stderr)
    sys.exit(1)
text = text.replace(token, repos[product])

markers = (
    "# TEMPLATE_WORKSTATION_SAVE_BEGIN",
    "# TEMPLATE_WORKSTATION_SAVE_END",
    "# TEMPLATE_WORKSTATION_RESTORE_BEGIN",
    "# TEMPLATE_WORKSTATION_RESTORE_END",
)
pairs = {
    markers[0]: markers[1],
    markers[2]: markers[3],
}
lines = text.splitlines(keepends=True)
out = []
waiting = None
seen = set()
for line in lines:
    token_line = line.strip()
    if waiting is None and token_line in pairs:
        if product == "server":
            waiting = pairs[token_line]
            seen.add(token_line)
            continue
        seen.add(token_line)
        continue
    if waiting is not None:
        if token_line == waiting:
            seen.add(token_line)
            waiting = None
        continue
    if product == "workstation" and token_line in pairs.values():
        seen.add(token_line)
        continue
    out.append(line)
if waiting is not None or seen != set(markers):
    print("marqueurs du poste incomplets", file=sys.stderr)
    sys.exit(1)
text = "".join(out)
if "TEMPLATE" in text or token in text:
    print("jeton encore présent", file=sys.stderr)
    sys.exit(1)
if product == "workstation" and "scan-skip.paths" not in text:
    print("bloc poste absent", file=sys.stderr)
    sys.exit(1)
if product == "server" and "scan-skip.paths" in text:
    print("bloc poste encore présent", file=sys.stderr)
    sys.exit(1)
if not text.endswith("\n"):
    text += "\n"
data = text.encode("utf-8")
if dest == "-":
    sys.stdout.buffer.write(data)
else:
    pathlib.Path(dest).write_bytes(data)
