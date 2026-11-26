#!/usr/bin/env python3
# =============================================================================
# File       : python/alert-decide.py
# Updated at : 2026-11-26
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Classify one watchdog phase and store its decision files.
# Note       : A package lookup asks dpkg. A missing package stays unexplained.
# -----------------------------------------------------------------------------


import datetime
import json
import os
import re
import subprocess
import sys
from pathlib import Path

PHASE_TOOLS = {
    "malware": {"clamav", "chkrootkit", "rkhunter"},
    "integrity": {"debsums", "auditd", "aide", "chkrootkit", "rkhunter"},
    "evergreen": {"clamav", "crowdsec", "fail2ban"},
}
LATE = {"aide.removed", "aide.package", "aide.conffile", "aide.unknown", "chk.unknown", "rk.unknown"}
UNKNOWN = {"aide": "aide.unknown", "chkrootkit": "chk.unknown", "rkhunter": "rk.unknown"}
TIMER_LINKS = {
    "/etc/systemd/system/timers.target.wants/w-boot-chain.timer",
    "/etc/systemd/system/timers.target.wants/w-periodic-scan.timer",
    "/etc/systemd/system/timers.target.wants/w-reboot-notice.timer",
    "/etc/systemd/system/timers.target.wants/s-boot-chain.timer",
    "/etc/systemd/system/timers.target.wants/s-periodic-scan.timer",
    "/etc/systemd/system/timers.target.wants/s-reboot-notice.timer",
}
# A timer this product adds is treated as expected.
added_timers = set()
AIDE_ENTRY = re.compile(r"^(?:[fdlcbpsDP!?][+.\-:=> <?A-Za-z]*:\s+\S|(?:added|removed|changed):\s+\S)")
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
INTERESTING = ("infected", "warning", "rootkit", "suspect", "promisc", "promiscuous", "preload")


def load_lines(path):
    if path is None or not path.is_file():
        return []
    found = []
    for raw in path.read_text(errors="replace").splitlines():
        line = raw.strip()
        if line and not line.startswith("#"):
            found.append(line)
    return found


def catalog_noise(raw):
    if not raw.strip() or raw.startswith("#"):
        return True
    if raw.endswith("<<") or raw.endswith(">>"):
        return True
    return False


def arm_skip(raw, current):
    if raw.endswith("<<"):
        current["_skip"] = True
    if raw.endswith(">>") and current is not None:
        current["_skip"] = False


def skip_catalog_line(raw, current):
    if not catalog_noise(raw):
        return False
    arm_skip(raw, current)
    return True


def take_catalog_line(raw, current, records):
    if raw.startswith("[") and raw.endswith("]"):
        current = {"id": raw[1:-1], "hold": "0", "tool": "", "match": r"$^"}
        records.append(current)
        return current
    if current is None or "=" not in raw:
        return current
    key, value = raw.split("=", 1)
    current[key.strip()] = value.strip()
    return current


def compile_catalog(records):
    for rec in records:
        rec["regex"] = re.compile(rec.get("match") or r"$^")


def load_catalog(path):
    records = []
    current = None
    if not path.is_file():
        return records
    for raw in path.read_text(errors="replace").splitlines():
        if skip_catalog_line(raw, current):
            continue
        if current is not None and current.get("_skip"):
            continue
        current = take_catalog_line(raw, current, records)
    compile_catalog(records)
    return records


def tool_of(name):
    low = name.lower()
    if low.startswith("crash-"):
        low = low[len("crash-") :]
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
    except (subprocess.CalledProcessError, OSError, FileNotFoundError):  # fmt: skip
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


def package_pattern(package):
    short = package.split(":", 1)[0]
    if not short:
        return None
    return re.compile(rf"(?<![A-Za-z0-9+.-]){re.escape(short)}(?::[A-Za-z0-9]+)?(?![A-Za-z0-9+.-])")


def apt_changed(name, apt_text, not_before):
    block_time = 0
    for raw in apt_text.splitlines():
        if raw.startswith("Start-Date:"):
            block_time = stamp_of(raw.split(":", 1)[1])
            continue
        if block_time and block_time >= not_before and name.search(raw):
            if raw.startswith(("Install:", "Upgrade:", "Remove:")):
                return True
    return False


def token_in(raw, needles):
    for token in needles:
        if token in raw:
            return True
    return False


def dpkg_changed(name, dpkg_text, not_before):
    for raw in dpkg_text.splitlines():
        moment = stamp_of(raw)
        if moment < not_before:
            continue
        if name.search(raw) and token_in(raw, (" install ", " upgrade ", " remove ")):
            return True
    return False


def package_changed(package, apt_text, dpkg_text, not_before):
    if not package:
        return False
    name = package_pattern(package)
    if name is None:
        return False
    if apt_changed(name, apt_text, not_before):
        return True
    return dpkg_changed(name, dpkg_text, not_before)


def snap_explains(path):
    if "/snap/" not in path and "snap-" not in os.path.basename(path):
        return False
    try:
        out = subprocess.check_output(["snap", "changes"], text=True, stderr=subprocess.DEVNULL)
    except (subprocess.CalledProcessError, OSError, FileNotFoundError):  # fmt: skip
        return False
    base = os.path.basename(path).replace("\\x2d", "-")
    token = re.sub(r"^snap-|-\d+\.mount$", "", base)
    return bool(token) and token in out


def specific_hit(tool, text, records):
    for rec in records:
        if rec.get("tool") == tool and rec["id"] not in LATE and rec["regex"].search(text):
            return rec
    return None


def unknown_hit(tool, records):
    chosen_id = UNKNOWN.get(tool, "")
    for rec in records:
        if rec["id"] == chosen_id:
            return rec
    return None


def classify_text(tool, text, records):
    chosen = specific_hit(tool, text, records)
    if chosen is None:
        chosen = unknown_hit(tool, records)
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


def paths_in(line):
    paths = []
    for path in PATH_TOKEN.findall(line):
        if not path.startswith("/proc/") and path not in paths:
            paths.append(path)
    return paths


def path_rows(tool, text, records, want):
    rows = []
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line or not want(line):
            continue
        class_id, hold = classify_text(tool, line, records)
        paths = paths_in(line) or ["-"]
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


def audit_paths(line):
    paths = []
    for path in PATH_TOKEN.findall(line):
        if path.startswith("/tmp") or path.startswith("/var/tmp") or path.startswith("/dev/shm"):
            paths.append(path)
    if not paths:
        return ["-"]
    return paths


def check_audit_exec(line):
    return "exec-tmp" in line or "EXECVE" in line


def check_audit_event(line):
    if "ANOM_" in line:
        return True
    if "res=failed" not in line:
        return False
    return "USER_LOGIN" in line or "USER_AUTH" in line


def audit_rows(text):
    rows = []
    for raw in text.splitlines():
        line = raw.strip()
        if check_audit_exec(line):
            for path in audit_paths(line):
                rows.append((path, "audit.exec", "1", "auditd"))
            continue
        if check_audit_event(line):
            rows.append(("-", "audit.event", "1", "auditd"))
    return rows


def ban_line_ok(tool, low):
    if tool == "fail2ban" and "ban" not in low:
        return False
    if tool == "crowdsec" and not any(token in low for token in ("ban", "decision", "scenario", "alert")):
        return False
    return True


def ban_scenario(low):
    match = re.search(r"scenario[:= ]+(\S+)", low)
    if not match:
        return ""
    return match.group(1).strip("',\"")


def ban_name(scenario, found_ips):
    if scenario:
        return scenario
    if found_ips:
        return found_ips[0]
    return "-"


def ban_path(found_ips):
    if found_ips:
        return found_ips[0]
    return "-"


def ban_row(tool, raw):
    line = raw.strip()
    low = line.lower()
    if not ban_line_ok(tool, low):
        return None
    found_ips = IP_TOKEN.findall(line)
    scenario = ban_scenario(low)
    if not found_ips and not scenario:
        return None
    label = scenario or "ban"
    return (ban_path(found_ips), label, "0", tool, ban_name(scenario, found_ips))


def ban_rows(tool, text, ips, scenarios):
    rows = []
    for raw in text.splitlines():
        row = ban_row(tool, raw)
        if row:
            rows.append(row)
    return rows


def crash_rows(tool, text):
    rows = []
    for raw in text.splitlines():
        if raw.strip():
            rows.append(("-", "crash", "1", tool))
            break
    return rows


def load_actions(path):
    if path is None or not path.is_file():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def case_steps(case, explained):
    key = "explained" if explained == "1" else "real"
    return [str(step) for step in case.get(key, [])]


def steps_of(item, tool, class_id, explained):
    if not isinstance(item, dict) or item.get("name") != tool:
        return None
    for case in item.get("cases", []):
        if case.get("id") != class_id:
            continue
        return case_steps(case, explained)
    return None


def actions_for(tool, class_id, explained):
    if not isinstance(action_table, dict):
        return []
    for item in action_table.get("watchdogs", []):
        steps = steps_of(item, tool, class_id, explained)
        if steps is not None:
            return steps
    return []


def line_interesting(line):
    low = line.lower()
    # The tool name chkrootkit contains the token rootkit. A whole word avoids that hit.
    return any(re.search(rf"\b{re.escape(token)}\b", low) for token in INTERESTING)


def with_blank(rows):
    return [(*row, "") for row in rows]


def tool_rows(tool, text):
    if tool == "aide":
        return with_blank(aide_rows(text, records))
    if tool == "clamav":
        return with_blank(clam_rows(text))
    if tool == "debsums":
        return debsums_rows(text)
    return more_rows(tool, text)


def more_rows(tool, text):
    if tool == "auditd":
        return with_blank(audit_rows(text))
    if tool in {"crowdsec", "fail2ban"}:
        return ban_rows(tool, text, ips, scenarios)
    if tool in {"chkrootkit", "rkhunter"}:
        return with_blank(path_rows(tool, text, records, line_interesting))
    return []


def rows_of(log, text):
    tool = tool_of(log.name)
    if log.name.startswith("crash-"):
        return with_blank(crash_rows(tool, text))
    return tool_rows(tool, text)


def keep_log(log):
    if tool_of(log.name) in wanted:
        return True
    return log.name.startswith("crash-")


def selected_logs():
    if log_directory and log_directory.is_file():
        return [log_directory]
    if not log_directory or not log_directory.is_dir():
        return []
    return sorted(path for path in log_directory.iterdir() if path.is_file())


def collect_found():
    found = []
    for log in selected_logs():
        if not keep_log(log):
            continue
        found.extend(rows_of(log, log.read_text(errors="replace")))
    return found


def ban_explained(path, class_id, tool, extra):
    if tool not in {"crowdsec", "fail2ban"}:
        return False
    if path != "-" and path in ips:
        return True
    if extra and extra.lower() in scenarios:
        return True
    return class_id.lower() in scenarios


def early_explained(path, banned):
    if path in added_timers:
        return "1"
    if path in repair or banned or (path != "-" and excluded_path(path, prefixes)):
        return "1"
    return ""


def package_explained(path, extra):
    package = extra or package_of("" if path == "-" else path)
    changed = package_changed(package, apt_text, dpkg_text, since)
    if changed or (path != "-" and snap_explains(path)):
        return "1"
    return "0"


def explained_flag(path, class_id, hold, tool, extra):
    early = early_explained(path, ban_explained(path, class_id, tool, extra))
    if early:
        return early
    if hold == "1" or tool not in {"aide", "chkrootkit", "rkhunter"}:
        return "0"
    return package_explained(path, extra)


def row_name(path, tool, extra):
    if extra:
        return extra
    if path == "-":
        return tool
    return package_of(path) or tool


def ban_kind(tool, extra, path):
    if tool == "fail2ban":
        kind = "jail"
    else:
        kind = "scenario"
    return kind, extra or path


def package_label(path, extra, name):
    found = extra or package_of(path)
    return "package", found or name


def shape_kind(path, tool, extra, name):
    if tool in {"fail2ban", "crowdsec"}:
        return ban_kind(tool, extra, path)
    if extra or (path != "-" and package_of(path)):
        return package_label(path, extra, name)
    return "file", name


def join_row(explained, hold, kind, name, path, tool, class_id):
    fields = [explained, hold, kind, name or "-", "-", path or "-", tool, class_id or "-"]
    return "\t".join(fields)


def one_row(item):
    path, class_id, hold, tool, extra = item
    explained = explained_flag(path, class_id, hold, tool, extra)
    kind, name = shape_kind(path, tool, extra, row_name(path, tool, extra))
    return explained, join_row(explained, hold, kind, name, path, tool, class_id)


def status_of(rows_out, real):
    if rows_out and real:
        return "real"
    if rows_out:
        return "false"
    return "clean"


def known_actions(rows_out):
    known = []
    for row in rows_out:
        parts = row.split("\t")
        if len(parts) < 8:
            continue
        actions = actions_for(parts[6], parts[7], parts[0])
        if actions:
            known.append(parts[6] + "\t" + parts[7] + "\t" + ",".join(actions))
    return known


def write_rows(path, rows):
    path.write_text(("\n".join(rows) + "\n") if rows else "")


def emit(found):
    rows_out = []
    real = False
    for item in found:
        explained, row = one_row(item)
        if explained == "0":
            real = True
        rows_out.append(row)
    status = status_of(rows_out, real)
    write_rows(state_directory / "rows.tsv", rows_out)
    (state_directory / "status").write_text(status + "\n")
    write_rows(state_directory / "actions.tsv", known_actions(rows_out))
    sys.stdout.write(status)


def prepare():
    global log_directory, since, repair, records, prefixes, ips, scenarios
    global apt_text, dpkg_text, wanted, state_directory, action_table
    log_directory = Path(sys.argv[2]) if sys.argv[2] else None
    since = int(sys.argv[3] or "0")
    repair_file = Path(sys.argv[4]) if sys.argv[4] else None
    action_path = Path(sys.argv[9]) if len(sys.argv) > 9 and sys.argv[9] else None
    state_directory = Path(sys.argv[8])
    action_table = load_actions(action_path)
    records = load_catalog(Path(sys.argv[5]))
    prefixes, ips, scenarios = excludes_of(os.environ.get("WATCHDOG_EXCLUDES", ""))
    repair = set(load_lines(repair_file))
    apt_text = history_text(Path(sys.argv[6]))
    dpkg_text = history_text(Path(sys.argv[7]))
    wanted = PHASE_TOOLS.get(sys.argv[1], set())


def run_alert_decide():
    prepare()
    emit(collect_found())


if __name__ == "__main__":
    run_alert_decide()
