#!/usr/bin/env python3
# =============================================================================
# File       : python/exclusions.py
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Read the workstation exclusion list and write tool fragments.
# -----------------------------------------------------------------------------


import datetime
import re
import sys
from pathlib import Path

TOOLS = ("clamav", "aide", "chkrootkit", "rkhunter", "alert")
BEGIN = "# BEGIN Liltress exclusions"
END = "# END Liltress exclusions"


def file_header():
    day = datetime.date.today().isoformat()
    return (
        "# =============================================================================\n"
        "# File       : config/service/exclusions/entries.yaml\n"
        f"# Updated at : {day}\n"
        "# Creator    : palarchsys\n"
        "# =============================================================================\n"
        "\n"
    )


def fail(code):
    print(code, file=sys.stderr)
    raise SystemExit(1)


def parse_scalar(text):
    text = text.strip()
    if text == "":
        return ""
    if text[0] == '"':
        return read_quoted(text)
    if text[0] == "[":
        return read_tools(text)
    return text


def read_quoted(text):
    out = []
    escaped = False
    for char in text[1:]:
        if escaped:
            out.append(char)
            escaped = False
            continue
        if char == "\\":
            escaped = True
            continue
        if char == '"':
            return "".join(out)
        out.append(char)
    fail("quote")
    return ""


def read_tools(text):
    if not text.endswith("]"):
        fail("tools")
    inner = text[1:-1].strip()
    if inner == "":
        return []
    return [part.strip() for part in inner.split(",") if part.strip()]


def split_field(text):
    if ":" not in text:
        fail("field")
    key, value = text.split(":", 1)
    return key.strip(), parse_scalar(value)


def take_entry(raw):
    needed = ("id", "path", "tools", "reason", "added", "expires")
    if any(key not in raw for key in needed):
        fail("field")
    entry = {key: raw[key] for key in needed}
    check_entry(entry)
    return entry


def skip_line(line):
    if line.startswith("#"):
        return True
    if not line.strip():
        return True
    return line.strip() == "---"


def empty_document(line, current, rows):
    if line.strip() != "entries: []":
        return False
    if current is not None:
        return False
    return not rows


def take_line(line, current, rows):
    if line.startswith("  - "):
        if current is not None:
            rows.append(take_entry(current))
        key, value = split_field(line[4:])
        return {key: value}
    if not line.startswith("    ") or current is None:
        fail("yaml")
    key, value = split_field(line.strip())
    current[key] = value
    return current


def parse_document(text):
    rows = []
    current = None
    for line in text.splitlines():
        if skip_line(line):
            continue
        if empty_document(line, current, rows):
            return []
        if line.strip() == "entries:":
            continue
        current = take_line(line, current, rows)
    if current is not None:
        rows.append(take_entry(current))
    return rows


def check_date(text, allow_empty):
    if text == "" and allow_empty:
        return
    try:
        datetime.date.fromisoformat(text)
    except ValueError:
        fail("date")


def check_path(path):
    if not path.startswith("/"):
        fail("path")
    if "\n" in path or "\x00" in path:
        fail("path")
    parts = [part for part in path.split("/") if part]
    if not parts or any(part == ".." for part in parts):
        fail("path")


def check_tools(tools):
    if not isinstance(tools, list) or not tools:
        fail("tools")
    if any(tool not in TOOLS for tool in tools):
        fail("tools")


def check_reason(reason):
    if not isinstance(reason, str):
        fail("reason")
    if not reason.strip() or "\n" in reason:
        fail("reason")


def check_entry(entry):
    if not re.fullmatch(r"ex-[0-9]{4,}", entry["id"]):
        fail("id")
    check_path(entry["path"])
    check_tools(entry["tools"])
    check_reason(entry["reason"])
    check_date(entry["added"], False)
    check_date(entry["expires"], True)


def quote_text(text):
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def write_entries(path, entries):
    lines = ["entries:"]
    if not entries:
        lines = ["entries: []"]
    for entry in entries:
        tools = ", ".join(entry["tools"])
        lines.append(f"  - id: {entry['id']}")
        lines.append(f"    path: {quote_text(entry['path'])}")
        lines.append(f"    tools: [{tools}]")
        lines.append(f"    reason: {quote_text(entry['reason'])}")
        lines.append(f"    added: {entry['added']}")
        lines.append(f"    expires: {entry['expires']}")
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(file_header() + "\n".join(lines) + "\n", encoding="utf-8")
    target.chmod(0o644)


def read_entries(path):
    target = Path(path)
    if not target.is_file():
        fail("yaml")
    return parse_document(target.read_text(encoding="utf-8"))


def active_entry(entry, today):
    if entry["expires"] == "":
        return True
    return entry["expires"] >= today


def next_id(entries):
    highest = 0
    for entry in entries:
        highest = max(highest, int(entry["id"].split("-", 1)[1]))
    return f"ex-{highest + 1:04d}"


def add_entry(path, file_path, tools, reason, today):
    entries = read_entries(path)
    entry = {
        "id": next_id(entries),
        "path": file_path,
        "tools": read_tools(tools if tools.startswith("[") else f"[{tools}]"),
        "reason": reason,
        "added": today,
        "expires": "",
    }
    check_entry(entry)
    entries.append(entry)
    write_entries(path, entries)
    print(entry["id"])


def remove_entry(path, entry_id):
    entries = read_entries(path)
    kept = [entry for entry in entries if entry["id"] != entry_id]
    if len(kept) == len(entries):
        fail("id")
    write_entries(path, kept)


def show_row(entry):
    expires = entry["expires"] or "-"
    tools = ",".join(entry["tools"])
    print(f"{entry['id']}\t{entry['path']}\t{tools}\t{entry['reason']}\t{entry['added']}\t{expires}")


def list_entries(path, tool):
    if tool and tool not in TOOLS:
        fail("tools")
    for entry in read_entries(path):
        if tool and tool not in entry["tools"]:
            continue
        show_row(entry)


def review_entries(path, today, days):
    limit = datetime.date.fromisoformat(today) - datetime.timedelta(days=int(days))
    for entry in read_entries(path):
        marks = review_marks(entry, today, limit)
        if marks:
            print(f"{','.join(marks)}\t", end="")
            show_row(entry)


def review_marks(entry, today, limit):
    marks = []
    added = datetime.date.fromisoformat(entry["added"])
    if added <= limit:
        marks.append("old")
    if entry["expires"] and entry["expires"] < today:
        marks.append("expired")
    return marks


def paths_for(entries, today, tool):
    found = []
    for entry in entries:
        if tool in entry["tools"] and active_entry(entry, today):
            found.append(entry["path"])
    return found


def write_lines(path, lines):
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    body = "\n".join(lines)
    if body:
        body += "\n"
    target.write_text(body, encoding="utf-8")
    target.chmod(0o644)


def render_fragments(path, out_directory, today):
    entries = read_entries(path)
    directory = Path(out_directory)
    write_lines(directory / "clamav-skip.paths", paths_for(entries, today, "clamav"))
    write_lines(directory / "aide.rules", [f"!{item}" for item in paths_for(entries, today, "aide")])
    patterns = [f"^{re.escape(item)}(/|$)" for item in paths_for(entries, today, "chkrootkit")]
    write_lines(directory / "chkrootkit.ignore", patterns)
    write_lines(directory / "rkhunter-allow.conf", rkhunter_lines(paths_for(entries, today, "rkhunter")))
    write_lines(directory / "alert-exclude.list", [alert_line(item) for item in paths_for(entries, today, "alert")])


def rkhunter_lines(paths):
    lines = []
    for path in paths:
        kind = "ALLOWHIDDENDIR" if path.endswith("/") or Path(path).is_dir() else "ALLOWHIDDENFILE"
        lines.append(f"{kind}={path}")
    return lines


def alert_line(path):
    if path.endswith("/") or Path(path).is_dir():
        return path if path.endswith("/") else f"{path}/"
    return path


def rule_lines(path):
    if not Path(path).is_file():
        return []
    lines = []
    for raw in Path(path).read_text(encoding="utf-8").splitlines():
        if raw.strip() and not raw.startswith("#"):
            lines.append(raw)
    return lines


def strip_block(text):
    pattern = re.compile(rf"{re.escape(BEGIN)}\n.*?{re.escape(END)}\n?", re.DOTALL)
    return pattern.sub("", text)


def splice_fragment(target, fragment):
    path = Path(target)
    if not path.is_file():
        return
    original = path.read_text(encoding="utf-8")
    stripped = strip_block(original)
    rules = rule_lines(fragment)
    if not rules:
        if stripped != original:
            path.write_text(stripped, encoding="utf-8")
        return
    body = stripped if stripped.endswith("\n") or stripped == "" else stripped + "\n"
    body += BEGIN + "\n" + "\n".join(rules) + "\n" + END + "\n"
    if body != original:
        path.write_text(body, encoding="utf-8")


def dispatch(argv):
    command = argv[1]
    if command == "add":
        add_entry(argv[2], argv[3], argv[4], argv[5], argv[6])
        return
    if command == "remove":
        remove_entry(argv[2], argv[3])
        return
    if command == "list":
        list_entries(argv[2], argv[3] if len(argv) > 3 else "")
        return
    if command == "review":
        review_entries(argv[2], argv[3], argv[4])
        return
    if command == "render":
        render_fragments(argv[2], argv[3], argv[4])
        return
    if command == "splice":
        splice_fragment(argv[2], argv[3])
        return
    fail("command")


if __name__ == "__main__":
    dispatch(sys.argv)
