#!/usr/bin/env python3
# =============================================================================
# File       : python/scan-skip-apply.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import re
import sys
from pathlib import Path

conf = Path(sys.argv[1])
dest = Path(sys.argv[2])
count = int(sys.argv[3])
fixed = sys.argv[4:4 + count]
paths = sys.argv[4 + count:]
seen = []
for path in list(fixed) + list(paths):
    if path and path not in seen:
        seen.append(path)
paths = seen
text = conf.read_text(errors="replace")
begin = "# BEGIN Liltress Workstation scan-skip"
end = "# END Liltress Workstation scan-skip"
old_begin = "# BEGIN High-Fortress User scan-skip"
old_end = "# END High-Fortress User scan-skip"
out = []
skipping = False
for line in text.splitlines():
    stripped = line.strip()
    if stripped in (begin, old_begin):
        skipping = True
        continue
    if skipping:
        if stripped in (end, old_end):
            skipping = False
        continue
    if line.startswith("OnAccessExcludePath "):
        continue
    out.append(line)
while out and out[-1] == "":
    out.pop()
block = [begin]
for path in paths:
    block.append("OnAccessExcludePath ^" + re.escape(path) + "$")
block.append(end)
out.append("")
out.extend(block)
new = "\n".join(out) + "\n"
old = text if text.endswith("\n") else text + "\n"
dest.write_text(new)
print("changed" if new != old else "same")
