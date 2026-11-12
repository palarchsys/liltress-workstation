#!/usr/bin/env python3
# =============================================================================
# File       : python/aide-home.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import sys

mode = sys.argv[1]
sys.argv = [sys.argv[0]] + sys.argv[2:]

if mode == 'server':
    import sys
    from pathlib import Path
    path, home = Path(sys.argv[1]), sys.argv[2].rstrip("/")
    text = path.read_text()
    begin = "# BEGIN Liltress account"
    end = "# END Liltress account"
    lines = text.splitlines()
    out = []
    skip = False
    for line in lines:
        if line.strip() == begin:
            skip = True
            continue
        if line.strip() == end:
            skip = False
            continue
        if not skip:
            out.append(line)
    names = [
        f"{home}/.ssh/authorized_keys",
        f"{home}/.bashrc",
        f"{home}/.profile",
        f"{home}/.bash_profile",
    ]
    existing = [name for name in names if Path(name).is_file()]
    if existing:
        block = [begin]
        block.extend(f"{name} All" for name in existing)
        block.append(end)
        out.extend(block)
    path.write_text("\n".join(out) + "\n")
elif mode == 'workstation':
    import sys
    from pathlib import Path
    path, home = Path(sys.argv[1]), sys.argv[2].rstrip("/")
    text = path.read_text()
    begin = "# BEGIN Liltress Workstation account"
    end = "# END Liltress Workstation account"
    old_begin = "# BEGIN High-Fortress User account"
    old_end = "# END High-Fortress User account"
    lines = text.splitlines()
    out = []
    skip = False
    for line in lines:
        if line.strip() in (begin, old_begin):
            skip = True
            continue
        if line.strip() in (end, old_end):
            skip = False
            continue
        if not skip:
            out.append(line)
    names = [
        f"{home}/.ssh/authorized_keys",
        f"{home}/.bashrc",
        f"{home}/.profile",
        f"{home}/.bash_profile",
        f"{home}/.config/autostart",
        f"{home}/.config/systemd/user",
    ]
    block = [begin]
    block.extend(f"{name} All" for name in names)
    block.append(f"!{home}/.ssh/known_hosts")
    block.append(f"!{home}/.ssh/known_hosts.old")
    block.append(end)
    out.extend(block)
    path.write_text("\n".join(out) + "\n")
else:
    sys.exit('mode python refusé')
