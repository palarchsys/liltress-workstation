#!/usr/bin/env python3
# =============================================================================
# File       : python/install-plan.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import sys

mode = sys.argv[1]
sys.argv = [sys.argv[0]] + sys.argv[2:]

if mode == 'index':
    import json, sys
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    needle = sys.argv[2]
    index = 0
    for category in data["categories"]:
        for step in category["steps"]:
            index += 1
            if needle in json.dumps(step, ensure_ascii=False):
                print(index)
                raise SystemExit(0)
    raise SystemExit(1)
elif mode == 'index':
    import json, sys
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    needle = sys.argv[2]
    index = 0
    for category in data["categories"]:
        for step in category["steps"]:
            index += 1
            if needle in json.dumps(step, ensure_ascii=False):
                print(index)
                raise SystemExit(0)
    raise SystemExit(1)
elif mode == 'usb-order':
    import json, sys
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    order = []
    for category in data["categories"]:
        for step in category["steps"]:
            order.append(step.get("path") or step.get("action"))
    def pos(name):
        return order.index(name) if name in order else -1
    ins, up, conf, aide = pos("service/usbguard/install.sh"), pos("apt-upgrade"), pos("service/usbguard/configure.sh"), pos("service/aide/init-db.sh")
    sys.exit(0 if ins >= 0 and up > ins and conf > up and aide > conf else 1)
elif mode == 'index':
    import json
    import sys
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    needle = sys.argv[2]
    index = 0
    for category in data["categories"]:
        for step in category["steps"]:
            index += 1
            blob = json.dumps(step, ensure_ascii=False)
            if needle in blob:
                print(index)
                raise SystemExit(0)
    raise SystemExit(1)
elif mode == 'paths':
    import json, sys
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    seen = []
    for category in data["categories"]:
        for step in category["steps"]:
            path = step.get("path")
            if path and path not in seen:
                seen.append(path)
                print(path)
elif mode == 'has-path':
    import json, sys
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    hits = [step for category in data["categories"] for step in category["steps"] if step.get("path") == "service/rclone/install.sh"]
    sys.exit(0 if hits else 1)
elif mode == 'vpn-order':
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
    if vpn != unbound + 1 or apparmor != vpn + 1:
        sys.exit("install hors place")
    if configure != ufw + 1:
        sys.exit("configure hors place")
elif mode == 'index':
    import json
    import sys
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    needle = sys.argv[2]
    index = 0
    for category in data["categories"]:
        for step in category["steps"]:
            index += 1
            blob = json.dumps(step, ensure_ascii=False)
            if needle in blob:
                print(index)
                raise SystemExit(0)
    raise SystemExit(1)
elif mode == 'paths':
    import json, sys
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    seen = []
    for category in data["categories"]:
        for step in category["steps"]:
            path = step.get("path")
            if path and path not in seen:
                seen.append(path)
                print(path)
elif mode == 'has-path':
    import json, sys
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    hits = [step for category in data["categories"] for step in category["steps"] if step.get("path") == "service/rclone/install.sh"]
    sys.exit(0 if hits else 1)
elif mode == 'steps':
    import json
    import sys

    allowed = {
        "MAIL_ALERTS",
        "SERVER_TYPE",
        "MODE_TEST",
        "MODE_DEV",
    }
    env_allowed = set()
    plan = json.load(open(sys.argv[1], encoding="utf-8"))
    for category in plan["categories"]:
        for step in category["steps"]:
            when = step.get("when") or {}
            var = when.get("var", "")
            eq = str(when.get("eq", ""))
            if var and var not in allowed:
                sys.exit("condition refusée : " + var)
            env = step.get("env") or {}
            for key in env:
                if key not in env_allowed:
                    sys.exit("environnement refusé : " + key)
            envspec = ",".join(f"{key}={env[key]}" for key in env)
            if "path" in step:
                kind, target = "path", step["path"]
            else:
                kind, target = "action", step["action"]
            print("\x1f".join([category["id"], step["id"], kind, target, var, eq, envspec]))
else:
    sys.exit('mode python refusé')
