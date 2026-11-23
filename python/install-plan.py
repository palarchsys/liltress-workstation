#!/usr/bin/env python3
# =============================================================================
# File       : python/install-plan.py
# Updated at : 2026-11-23
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Print one view of an install plan for the mode named on the command line.
# -----------------------------------------------------------------------------


import json
import sys
from pathlib import Path


def run_index_mode():
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


def get_step_index(order, name):
    if name in order:
        return order.index(name)
    return -1


def check_usb_order(ins, up, conf, aide):
    if ins < 0:
        return False
    if up <= ins:
        return False
    if conf <= up:
        return False
    return aide > conf


def run_usb_order():
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    order = []
    for category in data["categories"]:
        for step in category["steps"]:
            order.append(step.get("path") or step.get("action"))
    ins = get_step_index(order, "service/usbguard/install.sh")
    up = get_step_index(order, "apt-upgrade")
    conf = get_step_index(order, "service/usbguard/configure.sh")
    aide = get_step_index(order, "service/aide/init-db.sh")
    if check_usb_order(ins, up, conf, aide):
        sys.exit(0)
    sys.exit(1)


def run_plan_paths():
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    seen = []
    for category in data["categories"]:
        for step in category["steps"]:
            path = step.get("path")
            if path and path not in seen:
                seen.append(path)
                print(path)


def run_rclone_check():
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    hits = [
        step
        for category in data["categories"]
        for step in category["steps"]
        if step.get("path") == "service/rclone/install.sh"
    ]
    sys.exit(0 if hits else 1)


def run_vpn_order():
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


def get_step_when(step):
    when = step.get("when")
    if when:
        return when
    return {}


def get_step_env(step):
    env = step.get("env")
    if env:
        return env
    return {}


def run_plan_steps():
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
            when = get_step_when(step)
            var = when.get("var", "")
            eq = str(when.get("eq", ""))
            if var and var not in allowed:
                sys.exit("condition refusée : " + var)
            env = get_step_env(step)
            for key in env:
                if key not in env_allowed:
                    sys.exit("environnement refusé : " + key)
            envspec = ",".join(f"{key}={env[key]}" for key in env)
            if "path" in step:
                kind, target = "path", step["path"]
            else:
                kind, target = "action", step["action"]
            print("\x1f".join([category["id"], step["id"], kind, target, var, eq, envspec]))


def run_install_plan():
    mode = sys.argv[1]
    sys.argv = [sys.argv[0]] + sys.argv[2:]
    if mode == "index":
        run_index_mode()
    elif mode == "usb-order":
        run_usb_order()
    elif mode == "paths":
        run_plan_paths()
    elif mode == "has-path":
        run_rclone_check()
    elif mode == "vpn-order":
        run_vpn_order()
    elif mode == "steps":
        run_plan_steps()
    else:
        sys.exit("mode python refusé")


if __name__ == "__main__":
    run_install_plan()
