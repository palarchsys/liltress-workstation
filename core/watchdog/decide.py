#!/usr/bin/env python3
# =============================================================================
# File       : core/watchdog/decide.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import datetime
import os
import re
import subprocess
import sys
from pathlib import Path

phase = sys.argv[1]
log_dir = Path(sys.argv[2]) if sys.argv[2] else None
since = int(sys.argv[3] or "0")
repair_file = Path(sys.argv[4]) if sys.argv[4] else None
catalog_path = Path(sys.argv[5])
apt_path = Path(sys.argv[6])
dpkg_path = Path(sys.argv[7])
state_dir = Path(sys.argv[8])

action_path = Path(sys.argv[9]) if len(sys.argv) > 9 and sys.argv[9] else None
action_table = {}
if action_path is not None and action_path.is_file():
    import json
    action_table = json.loads(action_path.read_text(encoding="utf-8"))

PHASE_TOOLS = {
    "malware": {"clamav", "chkrootkit", "rkhunter"},
    "integrity": {"debsums", "auditd", "aide"},
    "evergreen": {"clamav", "crowdsec", "fail2ban"},
}
LATE = {"aide.removed", "aide.package", "aide.conffile", "aide.unknown", "chk.unknown", "rk.unknown"}
UNKNOWN = {"aide": "aide.unknown", "chkrootkit": "chk.unknown", "rkhunter": "rk.unknown"}
TIMER_LINKS = {
    "/etc/systemd/system/timers.target.wants/w-boot-chain.timer",
    "/etc/systemd/system/timers.target.wants/w-hourly-scan.timer",
    "/etc/systemd/system/timers.target.wants/w-idle-scan.timer",
    "/etc/systemd/system/timers.target.wants/w-periodic-scan.timer",
    "/etc/systemd/system/timers.target.wants/w-reboot-notice.timer",
    "/etc/systemd/system/timers.target.wants/s-boot-chain.timer",
    "/etc/systemd/system/timers.target.wants/s-hourly-scan.timer",
    "/etc/systemd/system/timers.target.wants/s-periodic-scan.timer",
    "/etc/systemd/system/timers.target.wants/s-reboot-notice.timer",
}
added_timers = set()
AIDE_ENTRY = re.compile(
    r"^(?:[fdlcbpsDP!?][+.\-:=> <?A-Za-z]*:\s+\S|(?:added|removed|changed):\s+\S)"
)
AIDE_PATH = re.compile(
    r"^(?:[fdlcbpsDP!?][+.\-:=> <?A-Za-z]*|(?:added|removed|changed)|"
    r"(?:File|Directory|FIFO|Link|Block device|Character device|Socket|Door|Port|"
    r"Unknown file type)):\s+(\S.*)$",
    re.I,
)
PATH_TOKEN = re.compile(r"(?<![A-Za-z0-9])(/(?:[\w.+@=-]|\\x[0-9A-Fa-f]{2})+(?:/(?:[\w.+@=-]|\\x[0-9A-Fa-f]{2})+)*)")
IP_TOKEN = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
PKG_LINE = re.compile(r"\(from ([A-Za-z0-9][A-Za-z0-9.+-]*(?::[A-Za-z0-9]+)?) package\)")
DEBSUM_PATH = re.compile(r"(?:changed|missing) file (\S+)")


def load_lines(path):
    if path is None or not path.is_file():
        return []
    found = []
    for raw in path.read_text(errors="replace").splitlines():
        line = raw.strip()
        if line and not line.startswith("#"):
            found.append(line)
    return found


def load_catalog(path):
    records = []
    current = None
    if not path.is_file():
        return records
    for raw in path.read_text(errors="replace").splitlines():
        if not raw.strip() or raw.startswith("#") or raw.endswith("<<") or raw.endswith(">>"):
            if raw.endswith("<<"):
                current["_skip"] = True
            if raw.endswith(">>") and current is not None:
                current["_skip"] = False
            continue
        if current is not None and current.get("_skip"):
            continue
        if raw.startswith("[") and raw.endswith("]"):
            current = {"id": raw[1:-1], "hold": "0", "tool": "", "match": r"$^"}
            records.append(current)
            continue
        if current is None or "=" not in raw:
            continue
        key, value = raw.split("=", 1)
        current[key.strip()] = value.strip()
    for rec in records:
        rec["regex"] = re.compile(rec.get("match") or r"$^")
    return records


def tool_of(name):
    low = name.lower()
    if low.startswith("crash-"):
        low = low[len("crash-"):]
    for token in ("chkrootkit", "rkhunter", "debsums", "auditd", "clamav", "crowdsec", "fail2ban", "aide"):
        if token in low:
            return token
    return ""


def excludes_of(spec):
    paths, ips, scenarios = [], [], []
    for chunk in (spec or "").split(":"):
        if not chunk:
            continue
        for line in load_lines(Path(chunk)):
            if line.startswith("ip:"):
                ips.append(line[3:].strip())
            elif line.startswith("scenario:"):
                scenarios.append(line[9:].strip().lower())
            else:
                paths.append(line)
    return paths, ips, scenarios


def excluded_path(path, prefixes):
    for prefix in prefixes:
        if path == prefix.rstrip("/") or path.startswith(prefix):
            return True
    return False


def package_of(path):
    if not path or path == "-":
        return ""
    try:
        out = subprocess.check_output(["dpkg", "-S", path], text=True, stderr=subprocess.DEVNULL)
    except (subprocess.CalledProcessError, OSError, FileNotFoundError):
        return ""
    token = out.split(":", 1)[0].split(",")[0].strip()
    if re.match(r"^[A-Za-z0-9][A-Za-z0-9.+-]*(?::[A-Za-z0-9]+)?$", token):
        return token
    return ""


def history_text(path):
    if not path.is_file():
        return ""
    return path.read_text(errors="replace")


def stamp_of(text):
    match = re.match(r"(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})", text.strip())
    if not match:
        return 0
    try:
        moment = datetime.datetime.strptime(match.group(1) + " " + match.group(2), "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return 0
    return int(moment.timestamp())


def package_changed(package, apt_text, dpkg_text, not_before):
    if not package:
        return False
    short = package.split(":", 1)[0]
    if not short:
        return False
    name = re.compile(rf"(?<![A-Za-z0-9+.-]){re.escape(short)}(?::[A-Za-z0-9]+)?(?![A-Za-z0-9+.-])")
    block_time = 0
    for raw in apt_text.splitlines():
        if raw.startswith("Start-Date:"):
            block_time = stamp_of(raw.split(":", 1)[1])
            continue
        if block_time and block_time >= not_before and name.search(raw):
            if raw.startswith(("Install:", "Upgrade:", "Remove:")):
                return True
    for raw in dpkg_text.splitlines():
        moment = stamp_of(raw)
        if moment < not_before:
            continue
        if name.search(raw) and any(token in raw for token in (" install ", " upgrade ", " remove ")):
            return True
    return False


def snap_explains(path):
    if "/snap/" not in path and "snap-" not in os.path.basename(path):
        return False
    try:
        out = subprocess.check_output(["snap", "changes"], text=True, stderr=subprocess.DEVNULL)
    except (subprocess.CalledProcessError, OSError, FileNotFoundError):
        return False
    base = os.path.basename(path).replace("\\x2d", "-")
    token = re.sub(r"^snap-|-\d+\.mount$", "", base)
    return bool(token) and token in out


def classify_text(tool, text, records):
    specific = [rec for rec in records if rec.get("tool") == tool and rec["id"] not in LATE]
    chosen = None
    for rec in specific:
        if rec["regex"].search(text):
            chosen = rec
            break
    if chosen is None:
        chosen_id = UNKNOWN.get(tool, "")
        for rec in records:
            if rec["id"] == chosen_id:
                chosen = rec
                break
    if chosen is None:
        return "", "1"
    return chosen["id"], chosen.get("hold", "0")


def aide_added(line):
    stripped = line.strip()
    low = stripped.lower()
    if low.startswith("added:"):
        return True
    if low.startswith(("removed:", "changed:")):
        return False
    head = stripped.split(":", 1)[0].strip()
    if len(head) < 2 or head[0] not in "fdlcbpsDP!?":
        return False
    return set(head[1:]) == {"+"}


def aide_rows(text, records):
    rows = []
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line or line[:1] in (" ", "\t"):
            continue
        if not AIDE_ENTRY.match(line):
            continue
        match = AIDE_PATH.match(line.strip())
        path = match.group(1).strip() if match else ""
        if path in TIMER_LINKS and aide_added(line):
            added_timers.add(path)
        class_id, hold = classify_text("aide", line, records)
        rows.append((path, class_id, hold, "aide"))
    return rows


def path_rows(tool, text, records, want):
    rows = []
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line or not want(line):
            continue
        paths = []
        for path in PATH_TOKEN.findall(line):
            if not path.startswith("/proc/") and path not in paths:
                paths.append(path)
        class_id, hold = classify_text(tool, line, records)
        if not paths:
            rows.append(("-", class_id, hold, tool))
            continue
        for path in paths:
            rows.append((path, class_id, hold, tool))
    return rows


def clam_rows(text):
    rows = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line.endswith("FOUND"):
            continue
        path = line.split(":", 1)[0].strip()
        if path.startswith("/"):
            rows.append((path, "clamav.found", "1", "clamav"))
    return rows


def debsums_rows(text):
    rows = []
    for raw in text.splitlines():
        line = raw.strip()
        named = PKG_LINE.search(line)
        found = DEBSUM_PATH.search(line)
        if found:
            rows.append((found.group(1), "debsums.file", "0", "debsums", named.group(1) if named else ""))
            continue
        if "réinstallé" in line or "reinstalled" in line.lower():
            token = line.split()[0]
            rows.append(("-", "debsums.repair", "0", "debsums", token))
    return rows


def audit_rows(text):
    rows = []
    for raw in text.splitlines():
        line = raw.strip()
        if "exec-tmp" not in line and "EXECVE" not in line:
            continue
        paths = [path for path in PATH_TOKEN.findall(line) if path.startswith("/tmp") or path.startswith("/var/tmp") or path.startswith("/dev/shm")]
        if not paths:
            paths = ["-"]
        for path in paths:
            rows.append((path, "audit.exec", "1", "auditd"))
    return rows


def ban_rows(tool, text, ips, scenarios):
    rows = []
    for raw in text.splitlines():
        line = raw.strip()
        low = line.lower()
        if tool == "fail2ban" and "ban" not in low:
            continue
        if tool == "crowdsec" and not any(token in low for token in ("ban", "decision", "scenario", "alert")):
            continue
        found_ips = IP_TOKEN.findall(line)
        scenario = ""
        match = re.search(r"scenario[:= ]+(\S+)", low)
        if match:
            scenario = match.group(1).strip("',\"")
        if not found_ips and not scenario:
            continue
        name = scenario or (found_ips[0] if found_ips else "-")
        kind_path = found_ips[0] if found_ips else "-"
        rows.append((kind_path, scenario or "ban", "0", tool, name))
    return rows


def crash_rows(tool, text):
    rows = []
    for raw in text.splitlines():
        if raw.strip():
            rows.append(("-", "crash", "1", tool))
            break
    return rows


records = load_catalog(catalog_path)
prefixes, ips, scenarios = excludes_of(os.environ.get("WATCHDOG_EXCLUDES", ""))
repair = set(load_lines(repair_file))
apt_text = history_text(apt_path)
dpkg_text = history_text(dpkg_path)
wanted = PHASE_TOOLS.get(phase, set())
found = []

logs = []
if log_dir and log_dir.is_file():
    logs = [log_dir]
elif log_dir and log_dir.is_dir():
    logs = sorted(path for path in log_dir.iterdir() if path.is_file())

for log in logs:
    tool = tool_of(log.name)
    if tool not in wanted and not log.name.startswith("crash-"):
        continue
    text = log.read_text(errors="replace")
    if log.name.startswith("crash-"):
        found.extend((path, class_id, hold, tool, "") for path, class_id, hold, tool in crash_rows(tool, text))
        continue
    if tool == "aide":
        found.extend((*row, "") for row in aide_rows(text, records))
    elif tool == "clamav":
        found.extend((*row, "") for row in clam_rows(text))
    elif tool == "debsums":
        found.extend(debsums_rows(text))
    elif tool == "auditd":
        found.extend((*row, "") for row in audit_rows(text))
    elif tool in {"crowdsec", "fail2ban"}:
        found.extend(ban_rows(tool, text, ips, scenarios))
    elif tool in {"chkrootkit", "rkhunter"}:
        def interesting(line, current=tool):
            low = line.lower()
            return any(token in low for token in ("infected", "warning", "rootkit", "suspect", "promisc", "preload"))

        found.extend((*row, "") for row in path_rows(tool, text, records, interesting))

rows_out = []
real = False
for path, class_id, hold, tool, extra in found:
    explained = "0"
    banned = tool in {"crowdsec", "fail2ban"} and (
        (path != "-" and path in ips) or (extra and extra.lower() in scenarios) or (class_id.lower() in scenarios)
    )
    if path in added_timers:
        explained = "1"
    elif path in repair or banned or (path != "-" and excluded_path(path, prefixes)):
        explained = "1"
    elif hold == "1" or tool not in {"aide", "chkrootkit", "rkhunter"}:
        explained = "0"
    else:
        package = extra or package_of(path if path != "-" else "")
        if package_changed(package, apt_text, dpkg_text, since) or (path != "-" and snap_explains(path)):
            explained = "1"
    if explained == "0":
        real = True
    kind = "file"
    name = extra or (package_of(path) if path != "-" else "") or tool
    if tool in {"fail2ban", "crowdsec"}:
        kind = "jail" if tool == "fail2ban" else "scenario"
        name = extra or path
    elif extra or (path != "-" and package_of(path)):
        kind = "package"
        name = extra or package_of(path) or name
    when = ""
    rows_out.append("\t".join([explained, hold, kind, name or "-", when or "-", path or "-", tool, class_id or "-"]))

status = "clean"
if rows_out and real:
    status = "real"
elif rows_out:
    status = "false"
(state_dir / "rows.tsv").write_text(("\n".join(rows_out) + "\n") if rows_out else "")
(state_dir / "status").write_text(status + "\n")
def actions_for(tool, class_id, explained):
    if not isinstance(action_table, dict):
        return []
    for item in action_table.get("watchdogs", []):
        if not isinstance(item, dict) or item.get("name") != tool:
            continue
        for case in item.get("cases", []):
            if case.get("id") != class_id:
                continue
            key = "explained" if explained == "1" else "real"
            return [str(step) for step in case.get(key, [])]
    return []

known = []
for row in rows_out:
    parts = row.split("\t")
    if len(parts) < 8:
        continue
    actions = actions_for(parts[6], parts[7], parts[0])
    if actions:
        known.append(parts[6] + "\t" + parts[7] + "\t" + ",".join(actions))
(state_dir / "actions.tsv").write_text(("\n".join(known) + "\n") if known else "")
sys.stdout.write(status)
