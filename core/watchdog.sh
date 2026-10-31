#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

if ! declare -F get_text >/dev/null 2>&1; then
    text_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    for text_candidate in \
        "${text_here}/log.sh" \
        "${G_CONFIG_BASE_DIRECTORY:-}/src/core/log.sh" \
        "${W_BASE:-}/src/core/log.sh" \
        "${G_BASE:-}/src/core/log.sh" \
        "${G_INSTALL_DIRECTORY:-}/core/log.sh" \
        "${G_PRODUCT_ROOT:-}/core/log.sh" \
        "${G_PRODUCT_ROOT:-}/../core/log.sh"
    do
        if [[ -n "${text_candidate}" && -f "${text_candidate}" ]]; then
            # shellcheck disable=SC1090
            source "${text_candidate}"
            break
        fi
    done
    unset text_candidate text_here
fi

get_product_base() {
    if [[ -n "${W_BASE:-}" ]]; then
        printf '%s' "${W_BASE}"
    elif [[ -n "${G_CONFIG_BASE_DIRECTORY:-}" ]]; then
        printf '%s' "${G_CONFIG_BASE_DIRECTORY}"
    elif [[ -n "${G_BASE:-}" ]]; then
        printf '%s' "${G_BASE}"
    else
        printf '%s' "/opt/liltress"
    fi
}

send_path() {
    if [[ -n "${CRON_BIN_PATH:-}" && -x "${CRON_BIN_PATH}/send.sh" ]]; then
        printf '%s\n' "${CRON_BIN_PATH}/send.sh"
        return 0
    fi
    local base
    base="$(get_product_base)"
    if [[ -x "${base}/cron/bin/send.sh" ]]; then
        printf '%s\n' "${base}/cron/bin/send.sh"
        return 0
    fi
    return 1
}

signal_phrase() {
    case "$1" in
        6) printf '%s' "$(get_text watchdog.signal.abort)" ;;
        7) printf '%s' "$(get_text watchdog.invalid-memory-access)" ;;
        9) printf '%s' "$(get_text watchdog.forced-stop)" ;;
        11) printf '%s' "$(get_text watchdog.internal-program-error)" ;;
        13) printf '%s' "$(get_text watchdog.interrupted-write)" ;;
        15) printf '%s' "$(get_text watchdog.stop-request)" ;;
        *) printf '%s' "$(get_text watchdog.signal "$1")" ;;
    esac
}

get_crash_sentence() {
    local label="$1"
    local status="$2"
    local signal phrase journal
    if [[ "${status}" -ge 128 ]]; then
        signal=$((status - 128))
        phrase="$(signal_phrase "${signal}")"
        printf "$(get_text watchdog.the-check-crashed-signal-it-did-not-finish "${label}" "${signal}" "${phrase}")"
    else
        printf "$(get_text watchdog.the-check-stopped-code-it-did-not-finish "${label}" "${status}")"
    fi
    journal="${LOG_FILE:-${LOG:-}}"
    if [[ -n "${journal}" ]]; then
        printf "$(get_text watchdog.the-journal-is "${journal}")"
    fi
    printf "$(get_text log.n)"
}

send_crash_mail() {
    local status=$?
    if [[ -n "${1-}" ]]; then
        status="$1"
    fi
    trap - EXIT
    [[ "${status}" -eq 0 ]] && return 0
    log_alert "$(get_crash_sentence "${G_CRASH_LABEL:-${W_CRASH_LABEL:-contrôle}}" "${status}")" || true
}

arm_crash_mail() {
    G_CRASH_LABEL="$1"
    W_CRASH_LABEL="$1"
    trap send_crash_mail EXIT
}

get_cpu_quota_percent() {
    local limit="${G_WATCHDOG_CPU_LIMIT:-50}"
    local n=1
    if [[ ! "${limit}" =~ ^[0-9]+$ ]]; then
        limit=50
    fi
    if command -v nproc >/dev/null 2>&1; then
        n="$(nproc 2>/dev/null)" || n=1
    fi
    if [[ ! "${n}" =~ ^[0-9]+$ ]] || [[ "${n}" -lt 1 ]]; then
        n=1
    fi
    printf '%s\n' "$((limit * n))"
}

run_limited() {
    local status=0 pid=0 lim=0 errexit=0
    local -a cmd=()
    case $- in
        *e*) errexit=1 ;;
    esac
    set +e
    if [[ "${G_LIMIT_WRAP:-1}" == "0" ]]; then
        "$@"
        status=$?
    else
        if command -v nice >/dev/null 2>&1; then
            cmd+=(nice -n "${G_WATCHDOG_LIMIT_NICE:-19}")
        fi
        if command -v ionice >/dev/null 2>&1; then
            cmd+=(ionice -c "${G_WATCHDOG_LIMIT_IO_NICE:-3}")
        fi
        if [[ "${#cmd[@]}" -eq 0 ]]; then
            "$@" &
        else
            "${cmd[@]}" "$@" &
        fi
        pid=$!
        if command -v cpulimit >/dev/null 2>&1; then
            cpulimit -p "${pid}" -l "$(get_cpu_quota_percent)" -z >/dev/null 2>&1 &
            lim=$!
        fi
        wait "${pid}"
        status=$?
        if [[ "${lim}" -ne 0 ]]; then
            kill "${lim}" 2>/dev/null
            wait "${lim}" 2>/dev/null
        fi
    fi
    if [[ "${errexit}" -eq 1 ]]; then
        set -e
    fi
    return "${status}"
}

get_alert_excerpt() {
    load_text "${G_LANGUAGE:-en}"
    G_TEXT_EXCERPT_MORE="$(get_text alert.excerpt.more)" \
    G_TEXT_EXCERPT_ATTR="$(get_text alert.excerpt.attr)" \
    G_TEXT_REDACTED="$(get_text mail.redacted)" \
    G_TEXT_REDACTED_KEY="$(get_text mail.redacted-key)" \
    python3 - "${1:-}" << 'PY'
import os
import re
import sys
from pathlib import Path

EXCERPT_MORE = os.environ.get(
    "G_TEXT_EXCERPT_MORE",
    "... {1} ligne(s) supplémentaire(s) non recopiées",
)
EXCERPT_ATTR = os.environ.get(
    "G_TEXT_EXCERPT_ATTR",
    "... {1} ligne(s) d'attribut supplémentaire(s) non recopiées",
)
REDACTED = os.environ.get("G_TEXT_REDACTED", "[masqué]")
REDACTED_KEY = os.environ.get("G_TEXT_REDACTED_KEY", "[clé privée masquée]")


def fill_count(template, count):
    def repl(match):
        if match.group(1) == "1":
            return str(count)
        return match.group(0)

    return re.sub(r"\{(\d+)\}", repl, template)

path = sys.argv[1]
raw = ""
if path and Path(path).is_file():
    raw = Path(path).read_text(errors="replace")

def redact(text):
    text = re.sub(
        r"(?is)-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----",
        lambda _match: REDACTED_KEY,
        text,
    )
    text = re.sub(
        r"(?i)\b(password|passwd|token|secret|api[_-]?key|authorization|bearer)\b(\s*[:=]\s*)\S+",
        lambda match: match.group(1) + match.group(2) + REDACTED,
        text,
    )
    text = re.sub(
        r"(?i)\bbearer\s+[A-Za-z0-9._~+/-]{8,}",
        lambda _match: "Bearer " + REDACTED,
        text,
    )
    return text

def clip(lines, limit=120):
    if len(lines) <= limit:
        return lines
    hidden = len(lines) - limit
    return lines[:limit] + [fill_count(EXCERPT_MORE, hidden)]

def format_aide(text):
    summary = re.compile(
        r"^(summary:|total number|added entries|removed entries|changed entries|"
        r"added, removed and changed entries|added and removed entries|"
        r"added and changed entries|removed and changed entries|"
        r"detailed information about changes|"
        r"aide found|start timestamp|end timestamp)\b",
        re.I,
    )
    # Type letter plus the summary field, or the plain added/removed/changed form.
    # The whole line is the path. A path line is never dropped.
    entry = re.compile(
        r"^(?:[fdlcbpsDP!?][+.\-:=> <?A-Za-z]*:\s+\S|(?:added|removed|changed):\s+\S)"
    )
    # Detail header. AIDE names the path again: "Link: /path", "Directory: /path".
    file_head = re.compile(
        r"^(?:file|directory|fifo|link|block device|character device|"
        r"socket|door|port|unknown file type):\s+\S",
        re.I,
    )
    diff_attrs = re.compile(
        r"^entry \S+ in databases has different attributes\b",
        re.I,
    )
    # Lines after this header describe aide.db, not a watched path.
    database = re.compile(
        r"^the attributes of the \(uncompressed\) database\b",
        re.I,
    )
    attr = re.compile(r"^\s+\S.*:")
    rows = []
    for line in text.splitlines():
        raw = line.rstrip()
        stripped = raw.strip()
        if not stripped:
            continue
        if database.match(stripped):
            break
        if (
            summary.match(stripped)
            or entry.match(raw)
            or file_head.match(raw)
            or diff_attrs.match(raw)
        ):
            rows.append(("keep", raw))
        elif attr.match(raw):
            rows.append(("attr", raw))
    out = []
    attr_left = 40
    hidden_attr = 0
    for kind, raw in rows:
        if kind == "keep":
            out.append(raw)
        elif attr_left > 0:
            out.append(raw)
            attr_left -= 1
        else:
            hidden_attr += 1
    if hidden_attr:
        out.append(fill_count(EXCERPT_ATTR, hidden_attr))
    return out

def format_named(name, text):
    low = name.lower()
    lines = [ln.rstrip() for ln in text.splitlines() if ln.strip()]
    if "aide" in low:
        picked = format_aide(text)
        return picked or clip(lines)
    if "rkhunter" in low:
        picked = []
        keep = False
        for raw in text.splitlines():
            line = raw.rstrip()
            stripped = line.strip()
            if not stripped:
                keep = False
                continue
            if re.search(r"Rootkit Hunter version", line, re.I):
                keep = False
                continue
            if re.match(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T", stripped):
                keep = False
                continue
            if re.search(r"warning|infected|rootkit|suspect|quarantaine", line, re.I):
                keep = True
                picked.append(line)
                continue
            if keep and (line[:1] in (" ", "\t") or stripped.startswith("/")):
                picked.append(line)
                continue
            keep = False
        return clip(picked)
    if "clam" in low:
        picked = []
        for raw in text.splitlines():
            line = raw.rstrip()
            stripped = line.strip()
            if not stripped:
                continue
            if re.match(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T", stripped):
                continue
            if re.search(
                r"Known viruses:|Infected files:|Engine version:|Scanned directories:|"
                r"Scanned files:|Data scanned:|Data read:|Time:|Start Date:|End Date:",
                line,
            ):
                continue
            if re.search(
                r"Access denied|Can't access|Can't open file|Permission denied|No such file",
                line,
                re.I,
            ):
                continue
            if "planté signal" in line or "contrôle arrêté" in line:
                picked.append(line)
                continue
            if stripped.endswith(" FOUND") or re.search(
                r"Signature|Fichier|Emplacement|Quarantaine", line
            ):
                picked.append(line)
                continue
            if re.search(r"ERROR:|LibClamAV", line):
                picked.append(line)
        return clip(picked)
    return clip(lines)

name = Path(path).name if path else ""
body = format_named(name, redact(raw))
if body:
    sys.stdout.write("\n".join(body))
PY
}

get_clamav_kind() {
    python3 - "${1:-}" << 'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1] else None
text = path.read_text(errors="replace") if path and path.is_file() else ""
if re.search(r" FOUND$", text, re.M):
    sys.stdout.write("infected")
    raise SystemExit(0)
access = re.compile(
    r"Access denied|Can't access|Can't open file|Permission denied|No such file",
    re.I,
)
summary = re.compile(
    r"Known viruses:|Infected files:|Engine version:|Scanned directories:|"
    r"Scanned files:|Data scanned:|Data read:|^Time:|Start Date:|End Date:"
)
real = False
for raw in text.splitlines():
    line = raw.strip()
    if not line or summary.search(line) or access.search(line):
        continue
    if line.startswith("-----------") or re.match(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T", line):
        continue
    if re.search(r"ERROR:|LibClamAV", line):
        real = True
if real:
    sys.stdout.write("error")
else:
    sys.stdout.write("ok")
PY
}

invoke_clamav() {
    if [[ "${G_CLAM_MODE:-scan}" == "daemon" ]]; then
        run_limited clamdscan --fdpass --infected --no-summary -- "$@"
    else
        clamscan --infected --no-summary -- "$@"
    fi
}

scan_clamav_batch() {
    local status=0 signal=0 streak=0 path errexit=0 tool="clamscan"
    [[ "$#" -gt 0 ]] || return 0
    if [[ "${G_CLAM_MODE:-scan}" == "daemon" ]]; then
        tool="clamdscan"
    fi
    case $- in
        *e*) errexit=1 ;;
    esac
    set +e
    invoke_clamav "$@"
    status=$?
    if [[ "${errexit}" -eq 1 ]]; then
        set -e
    fi
    if [[ "${status}" -lt 128 ]]; then
        return 0
    fi
    streak=0
    for path in "$@"; do
        set +e
        invoke_clamav "${path}"
        status=$?
        if [[ "${errexit}" -eq 1 ]]; then
            set -e
        fi
        if [[ "${status}" -ge 128 ]]; then
            signal=$((status - 128))
            printf '%s planté signal %s sur %s\n' "${tool}" "${signal}" "${path}"
            streak=$((streak + 1))
            if [[ "${streak}" -ge 2 ]]; then
                printf '%s planté signal %s, contrôle arrêté\n' "${tool}" "${signal}"
                G_CLAM_STOP=1
                W_CLAMAV_STOP=1
                return 0
            fi
        else
            streak=0
        fi
    done
    return 0
}

list_clamav_scan() {
    local file_list="$1"
    local path batch_max
    local -a batch=()
    batch_max="${G_CLAM_BATCH:-80}"
    G_CLAM_STOP=0
    W_CLAMAV_STOP=0
    while IFS= read -r -d '' path || [[ -n "${path}" ]]; do
        [[ -n "${path}" ]] || continue
        batch+=("${path}")
        if [[ "${#batch[@]}" -eq "${batch_max}" ]]; then
            scan_clamav_batch "${batch[@]}" || true
            batch=()
            [[ "${G_CLAM_STOP}" == 1 ]] && break
        fi
    done < "${file_list}"
    if [[ "${#batch[@]}" -gt 0 && "${G_CLAM_STOP}" != 1 ]]; then
        scan_clamav_batch "${batch[@]}" || true
    fi
    return 0
}

prepare_rkhunter_note() {
    local base
    base="$(get_product_base)"
    NOTE="$(get_text alert.note.rkhunter)"
    NOTE_CMD="sudo bash ${base}/bin/rkhunter-refresh-db.sh"
}

repair_debsums_log() {
    local log="$1"
    local summary=""
    [[ -n "${log}" && -s "${log}" ]] || return 0
    summary="$(
        python3 - "${log}" << 'PY' || true
import hashlib
import io
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

log_path = Path(sys.argv[1])
name_re = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.+-]*(?::[A-Za-z0-9]+)?$")
pkg_re = re.compile(
    r"\(from ([A-Za-z0-9][A-Za-z0-9.+-]*(?::[A-Za-z0-9]+)?) package\)\s*$"
)
path_re = re.compile(r"^debsums: changed file (.+?) \(from ")

def package_of(path):
    try:
        out = subprocess.check_output(
            ["dpkg", "-S", path], text=True, stderr=subprocess.DEVNULL
        )
    except (subprocess.CalledProcessError, OSError):
        return ""
    token = out.split(":", 1)[0].split(",")[0].strip()
    return token if name_re.match(token) else ""

packages = []
seen = set()
leftover = []
for raw in log_path.read_text(errors="replace").splitlines():
    line = raw.strip()
    if not line:
        continue
    named = pkg_re.search(line)
    if named and named.group(1) not in seen:
        seen.add(named.group(1))
        packages.append(named.group(1))
        continue
    found = path_re.match(line)
    path = found.group(1).strip() if found else (line if line.startswith("/") else "")
    pkg = package_of(path) if path else ""
    if pkg and pkg not in seen:
        seen.add(pkg)
        packages.append(pkg)
        continue
    if line not in leftover:
        leftover.append(line)

def run(cmd):
    env = os.environ.copy()
    env["DEBIAN_FRONTEND"] = "noninteractive"
    env["NEEDRESTART_MODE"] = "l"
    env["APT_LISTCHANGES_FRONTEND"] = "none"
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)

cache_dir = None

def purge_cache():
    # Une différence ne repasse pas par le cache apt. Il est purgé avant le téléchargement.
    run(["apt-get", "clean"])
    for root in (Path("/var/cache/apt/archives"), Path("/var/cache/apt/archives/partial")):
        if not root.is_dir():
            continue
        try:
            entries = list(root.iterdir())
        except OSError:
            continue
        for path in entries:
            if path.is_file() and ".deb" in path.name:
                try:
                    path.unlink()
                except OSError:
                    pass

def private_cache():
    global cache_dir
    if cache_dir is None:
        cache_dir = Path(tempfile.mkdtemp(prefix="hf-apt-"))
        (cache_dir / "partial").mkdir()
    return cache_dir

def reinstall(pkg):
    archives = private_cache()
    return run([
        "apt-get", "-o", f"Dir::Cache::archives={archives}/",
        "install", "--reinstall", "-y", "--", pkg,
    ])

def fresh_debs(pkg):
    if cache_dir is None or not cache_dir.is_dir():
        return []
    prefix = pkg.split(":", 1)[0] + "_"
    found = []
    try:
        entries = list(cache_dir.iterdir())
    except OSError:
        return []
    for path in entries:
        if path.is_file() and path.suffix == ".deb" and path.name.startswith(prefix):
            found.append(path)
    return found

def sums_ok(check):
    return check.returncode == 0 and not check.stdout.strip()

def failing_paths(text):
    found = []
    pattern = re.compile(r"(?:changed|missing) file (\S+)")
    for raw in text.splitlines():
        line = raw.strip()
        named = pattern.search(line)
        if named:
            found.append(named.group(1))
        elif line.startswith("/"):
            found.append(line.split()[0])
    return found

def archive_member(deb, rel):
    proc = subprocess.run(
        ["dpkg-deb", "--fsys-tarfile", str(deb)],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if proc.returncode != 0:
        return None
    want = rel.lstrip("/")
    try:
        tf = tarfile.open(fileobj=io.BytesIO(proc.stdout), mode="r|*")
    except tarfile.TarError:
        return None
    while True:
        try:
            member = tf.next()
        except tarfile.TarError:
            return None
        if member is None:
            return None
        if member.name.lstrip("./") != want:
            continue
        if member.issym() or member.islnk():
            return ("link", member.linkname)
        if member.isfile():
            extracted = tf.extractfile(member)
            return ("file", extracted.read() if extracted else b"")
        return None

def disk_matches_archive(deb, path):
    member = archive_member(deb, path)
    disk = Path(path)
    if member is None:
        return not disk.exists()
    kind, payload = member
    if kind == "link":
        return disk.is_symlink() and os.readlink(disk) == payload
    if disk.is_symlink() or not disk.is_file():
        return False
    return hashlib.md5(disk.read_bytes()).hexdigest() == hashlib.md5(payload).hexdigest()

def archive_explains(pkg, text):
    try:
        paths = failing_paths(text)
        debs = fresh_debs(pkg)
        if not paths or not debs:
            return False
        deb = max(debs, key=lambda path: path.stat().st_mtime)
        return all(disk_matches_archive(deb, path) for path in paths)
    except OSError:
        return False

blocks = []
restored = []
failed = []
try:
    if packages:
        purge_cache()
    for pkg in packages:
        apt = reinstall(pkg)
        if apt.returncode != 0:
            failed.append(pkg)
            err = next((ln.strip() for ln in reversed(apt.stdout.splitlines()) if ln.strip()), "apt-get a échoué")
            blocks.extend([f"{pkg} : réinstallation échouée.", err, ""])
            continue
        check = run(["debsums", "-s", pkg])
        if sums_ok(check):
            restored.append(pkg)
            blocks.extend([f"{pkg} réinstallé.", "La somme correspond.", ""])
        elif archive_explains(pkg, check.stdout):
            continue
        else:
            failed.append(pkg)
            detail = [
                ln.strip()
                for ln in check.stdout.splitlines()
                if ln.strip() and (" file " in ln or ln.strip().startswith("/"))
            ]
            blocks.extend([f"{pkg} réinstallé.", "La somme reste différente.", *detail, ""])
    for line in leftover:
        failed.append(line)
        blocks.extend([line, ""])

    report = "\n".join(blocks).rstrip()
    log_path.write_text((report + "\n") if report else "")
    if restored and not failed:
        if len(restored) == 1:
            sys.stdout.write(f"debsums : {restored[0]} réinstallé, somme rétablie")
        else:
            sys.stdout.write(f"debsums : {len(restored)} paquets réinstallés, sommes rétablies")
    elif restored or failed:
        sys.stdout.write("debsums : correction incomplète")
finally:
    if cache_dir is not None:
        shutil.rmtree(cache_dir, ignore_errors=True)
PY
    )"
    printf '%s' "${summary}"
}

record_quarantine_origin() {
    local source="$1"
    local origin="$2"
    local stored="$3"
    local signature="${4:-}"
    local base dir registry id moment quoted
    [[ -n "${stored}" && "${stored}" != "absent" && "${stored}" != "inconnue" ]] || return 0
    [[ "${origin}" == /* && "${origin}" != "${stored}" ]] || return 0
    id="$(basename -- "${stored}")"
    [[ "${id}" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+- ]] || return 0
    base="$(get_product_base)"
    dir="${base}/cron"
    registry="${dir}/quarantine.registry"
    if [[ ! -d "${dir}" ]]; then
        mkdir -p "${dir}" 2>/dev/null || return 0
    fi
    [[ -w "${dir}" ]] || return 0
    source="${source//$'\t'/ }"
    origin="${origin//$'\t'/ }"
    stored="${stored//$'\t'/ }"
    signature="${signature//$'\t'/ }"
    signature="${signature//$'\n'/ }"
    moment="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
    printf "$(get_text watchdog.t-t-t-t-t "${id}" "${moment}" "${source}" "${origin}" "${stored}" "${signature}")" \
        >> "${registry}" || return 0
    chmod 600 "${registry}" 2>/dev/null || true
    quoted="$(printf '%q' "${id}")"
    printf '%s\n' "sudo bash ${base}/bin/quarantine-restore.sh ${quoted}" >> "${dir}/quarantine.pending" || return 0
    chmod 600 "${dir}/quarantine.pending" 2>/dev/null || true
    return 0
}

queue_existing_restore() {
    local stored="$1"
    local base registry id quoted
    [[ -n "${stored}" && "${stored}" == /* ]] || return 0
    base="$(get_product_base)"
    registry="${base}/cron/quarantine.registry"
    [[ -f "${registry}" && -r "${registry}" ]] || return 0
    id="$(awk -F '\t' -v want="${stored}" '$5 == want { print $1; exit }' "${registry}" 2>/dev/null || true)"
    [[ -n "${id}" ]] || return 0
    [[ -w "${base}/cron" ]] || return 0
    quoted="$(printf '%q' "${id}")"
    printf '%s\n' "sudo bash ${base}/bin/quarantine-restore.sh ${quoted}" >> "${base}/cron/quarantine.pending" || return 0
    chmod 600 "${base}/cron/quarantine.pending" 2>/dev/null || true
    return 0
}

take_quarantine_note() {
    local pending body
    pending="$(get_product_base)/cron/quarantine.pending"
    [[ -s "${pending}" ]] || return 1
    body="$(cat "${pending}" 2>/dev/null || true)"
    [[ -n "${body}" ]] || return 1
    NOTE="$(get_text alert.note.quarantine)"
    NOTE_CMD="${body}"
    rm -f "${pending}" 2>/dev/null || true
    return 0
}

read_quarantine_holder() {
    local target="$1"
    local pid=""
    if command -v lsof >/dev/null 2>&1; then
        pid="$(lsof -t -- "${target}" 2>/dev/null | head -n 1 || true)"
    fi
    if [[ -z "${pid}" ]] && command -v fuser >/dev/null 2>&1; then
        pid="$(fuser -- "${target}" 2>/dev/null | awk '{print $1; exit}' || true)"
    fi
    printf '%s\n' "${pid}"
}

quarantine_holder_block() {
    local target="$1"
    shift
    local pid="" comm="" uid="" name=""
    G_QUARANTINE_PID=""
    G_QUARANTINE_COMM=""
    pid="$(read_quarantine_holder "${target}")"
    [[ -n "${pid}" && "${pid}" =~ ^[0-9]+$ ]] || return 1
    if [[ "${pid}" == "1" ]]; then
        printf '%s\n' "pid 1"
        return 0
    fi
    uid="$(stat -c '%u' "/proc/${pid}" 2>/dev/null || true)"
    if [[ -z "${uid}" || "${uid}" == "0" ]]; then
        printf '%s\n' "uid 0"
        return 0
    fi
    comm="$(cat "/proc/${pid}/comm" 2>/dev/null || true)"
    if [[ -z "${comm}" ]]; then
        printf '%s\n' "$(get_text watchdog.name-absent)"
        return 0
    fi
    for name in "$@"; do
        if [[ "${comm}" == "${name}" || "${comm}" == "${name}"* ]]; then
            printf '%s\n' "${comm}"
            return 0
        fi
    done
    G_QUARANTINE_PID="${pid}"
    G_QUARANTINE_COMM="${comm}"
    return 1
}

move_quarantine_file() {
    local origin="$1"
    local quarantine base stamp dest
    quarantine="${W_CLAMAV_QUARANTINE_DIR:-/var/lib/clamav/quarantine}"
    G_MOVE_ACTION="déplacement refusé"
    G_MOVE_STORED="${origin}"
    base="$(basename -- "${origin}")"
    [[ -n "${base}" && "${base}" != "/" && "${base}" != "." ]] || base="inconnu"
    if [[ ! -d "${quarantine}" ]]; then
        if id clamav >/dev/null 2>&1; then
            install -d -m 750 -o clamav -g clamav "${quarantine}" 2>/dev/null || true
        else
            install -d -m 750 "${quarantine}" 2>/dev/null || true
        fi
    fi
    if [[ ! -d "${quarantine}" || ! -w "${quarantine}" ]]; then
        return 0
    fi
    if [[ ! -e "${origin}" ]]; then
        G_MOVE_ACTION="fichier déjà absent"
        G_MOVE_STORED="absent"
        return 0
    fi
    if [[ ! -f "${origin}" || -L "${origin}" ]]; then
        return 0
    fi
    stamp="$(date +%Y%m%d-%H%M%S-%N)"
    dest="${quarantine}/${stamp}-${base}"
    if mv -- "${origin}" "${dest}"; then
        G_MOVE_ACTION="déplacé en quarantaine"
        G_MOVE_STORED="${dest}"
    else
        G_MOVE_STORED="${origin}"
    fi
    return 0
}

signal_quarantine_holder() {
    local origin="$1"
    local stored="$2"
    shift 2
    local target pid comm reason
    for target in "${origin}" "${stored}"; do
        [[ -n "${target}" && "${target}" != "absent" && -e "${target}" ]] || continue
        if reason="$(quarantine_holder_block "${target}" "$@")"; then
            printf '%s\n' "$(get_text watchdog.process-not-stopped "${reason}")"
            return 0
        fi
        pid="${G_QUARANTINE_PID:-}"
        comm="${G_QUARANTINE_COMM:-}"
        [[ -n "${pid}" ]] || continue
        if kill -TERM "${pid}" 2>/dev/null; then
            printf '%s\n' "$(get_text watchdog.process-stopped "${pid}" "${comm}")"
        else
            printf '%s\n' "$(get_text watchdog.process-not-stopped-signal-rejected "${pid}")"
        fi
        return 0
    done
    printf '%s\n' "$(get_text watchdog.process-not-stopped-no-d-tenteur)"
}

quarantine_confirmed_log() {
    local source="$1"
    local log="$2"
    shift 2
    local path reason phrase quarantine
    G_CONFIRMED_COUNT=0
    G_MOVED_COUNT=0
    [[ -n "${log}" && -f "${log}" ]] || return 0
    quarantine="${W_CLAMAV_QUARANTINE_DIR:-/var/lib/clamav/quarantine}"
    while IFS= read -r path; do
        [[ -n "${path}" ]] || continue
        case "${path}" in
            "${quarantine}"|"${quarantine}"/*) continue ;;
        esac
        [[ -f "${path}" && ! -L "${path}" ]] || continue
        G_CONFIRMED_COUNT=$((G_CONFIRMED_COUNT + 1))
        case "${path}" in
            /etc/passwd|/etc/shadow|/etc/sudoers|/etc/ssh/sshd_config|/etc/ufw/ufw.conf|/usr/bin/sudo|/usr/bin/passwd|/usr/sbin/sshd)
                printf '%s\n' "$(get_text watchdog.not-updated-in-quarantine "${path}")"
                continue
                ;;
        esac
        if reason="$(quarantine_holder_block "${path}" "$@")"; then
            printf '%s\n' "$(get_text watchdog.not-updated-in-quarantine "${reason}")"
            continue
        fi
        move_quarantine_file "${path}"
        if [[ "${G_MOVE_ACTION}" != "déplacé en quarantaine" ]]; then
            printf '%s\n' "${G_MOVE_ACTION} : ${path}"
            continue
        fi
        record_quarantine_origin "${source}" "${path}" "${G_MOVE_STORED}" "${source}" || true
        phrase="$(signal_quarantine_holder "${path}" "${G_MOVE_STORED}" "$@")"
        printf '%s\n' "$(get_text watchdog.moved-in-quarantine-quarantine "${path}" "${phrase}" "${G_MOVE_STORED}")"
        G_MOVED_COUNT=$((G_MOVED_COUNT + 1))
    done < <(python3 - "${source}" "${log}" << 'PY'
import re
import sys
from pathlib import Path

source = sys.argv[1]
log_path = Path(sys.argv[2])
text = log_path.read_text(errors="replace") if log_path.is_file() else ""
path_re = re.compile(r"(/[^\s<>|,;]+)")
seen = []
for raw in text.splitlines():
    line = raw.rstrip()
    if source == "rkhunter":
        if "Rootkit Hunter" in line:
            hit = "INFECTED" in line
        else:
            hit = ("INFECTED" in line) or ("Rootkit" in line)
    else:
        hit = "INFECTED" in line
    if not hit:
        continue
    for match in path_re.findall(line):
        path = match.rstrip(".,:)")
        if path not in seen:
            seen.append(path)
if seen:
    sys.stdout.write("\n".join(seen) + "\n")
PY
    )
    return 0
}

format_egress_body() {
    local kernel="$1"
    local audit="${2:-}"
    G_EGRESS_AUDIT_FILE="${audit}" python3 - "${kernel}" << 'PY'
import os
import re
import sys
from pathlib import Path

kernel_path = Path(sys.argv[1])
audit_path = os.environ.get("G_EGRESS_AUDIT_FILE", "")
kernel_lines = []
seen = set()
if kernel_path.is_file():
    for raw in kernel_path.read_text(errors="replace").splitlines():
        line = raw.rstrip("\n")
        if not line.strip() or line in seen:
            continue
        seen.add(line)
        kernel_lines.append(line)

audit_text = ""
if audit_path and Path(audit_path).is_file():
    audit_text = Path(audit_path).read_text(errors="replace")

def parse_sockaddr(token):
    token = token.strip().strip('"')
    if token.lower().startswith("saddr="):
        token = token.split("=", 1)[1]
    host = re.search(r"host:([0-9A-Fa-f:.]+)", token)
    serv = re.search(r"serv:([0-9]+)", token)
    if host and serv:
        return host.group(1), serv.group(1)
    if not re.fullmatch(r"[0-9A-Fa-f]+", token) or len(token) < 16 or len(token) % 2:
        return None
    raw = bytes.fromhex(token)
    if len(raw) < 8:
        return None
    family = int.from_bytes(raw[0:2], "little")
    port = str(int.from_bytes(raw[2:4], "big"))
    if family == 2 and len(raw) >= 8:
        ip = ".".join(str(b) for b in raw[4:8])
        return ip, port
    return None

events = {}
order = []
for raw in audit_text.splitlines():
    line = raw.strip()
    msg = re.search(r"msg=audit\(([^)]+)\):", line)
    if not msg:
        continue
    key = msg.group(1)
    if key not in events:
        events[key] = {}
        order.append(key)
    event = events[key]
    if line.startswith("type=SYSCALL"):
        comm = re.search(r'comm="([^"]+)"', line) or re.search(r"comm=(\S+)", line)
        pid = re.search(r"\bpid=([0-9]+)", line)
        uid = re.search(r"\buid=([0-9]+)", line)
        if comm:
            event["comm"] = comm.group(1)
        if pid:
            event["pid"] = pid.group(1)
        if uid:
            event["uid"] = uid.group(1)
    if "saddr=" in line or "host:" in line:
        sock = re.search(r"saddr=(\S+)", line)
        parsed = parse_sockaddr(sock.group(1) if sock else line)
        if parsed:
            event["dst"] = parsed

flows = {}
for key in order:
    event = events[key]
    dst = event.get("dst")
    if not dst or "pid" not in event:
        continue
    flows[dst] = (event.get("comm") or "inconnu", event["pid"], event.get("uid") or "0")

def emit_plain(lines):
    chosen = lines[:40]
    if chosen:
        sys.stdout.write("\n".join(chosen) + "\n")

if not flows:
    emit_plain(kernel_lines)
    raise SystemExit(0)

groups = []
index = {}
unmatched = []
for line in kernel_lines:
    dst = re.search(r"\bDST=(\S+)", line)
    dpt = re.search(r"\bDPT=([0-9]+)", line)
    proc = None
    if dst and dpt:
        proc = flows.get((dst.group(1), dpt.group(1)))
    if proc is None:
        unmatched.append(line)
        continue
    label = "Processus : %s (pid %s) uid %s" % (proc[0], proc[1], proc[2])
    if label not in index:
        if len(groups) >= 40:
            continue
        index[label] = len(groups)
        groups.append([label, []])
    groups[index[label]][1].append(line)

if unmatched and len(groups) < 40:
    groups.append(["Processus : non associé", unmatched])

blocks = []
for label, lines in groups:
    blocks.append(label)
    for line in lines:
        blocks.append(" → " + line)
if blocks:
    sys.stdout.write("\n".join(blocks) + "\n")
PY
}

get_alert_tool() {
    local module="${1:-}"
    local log="${2:-}"
    local summary="${3:-}"
    local base
    case "${module}" in
        aide|Aide|AIDE) printf '%s\n' aide; return 0 ;;
        chkrootkit|Chkrootkit|CHKROOTKIT) printf '%s\n' chkrootkit; return 0 ;;
        rkhunter|Rkhunter|RKHUNTER) printf '%s\n' rkhunter; return 0 ;;
    esac
    base="$(basename -- "${log:-}" 2>/dev/null || true)"
    case "${base}" in
        aide-*|*_aide|*_aide.log) printf '%s\n' aide; return 0 ;;
        chkrootkit-*|*_chkrootkit|*_chkrootkit.log) printf '%s\n' chkrootkit; return 0 ;;
        rkhunter-*|*_rkhunter|*_rkhunter.log) printf '%s\n' rkhunter; return 0 ;;
    esac
    case "${summary}" in
        AIDE:*|AIDE\ *) printf '%s\n' aide; return 0 ;;
        chkrootkit*) printf '%s\n' chkrootkit; return 0 ;;
        rkhunter*|mirrors.dat*) printf '%s\n' rkhunter; return 0 ;;
    esac
    return 1
}

render_alert_advice() {
    local tool="${1:-}"
    local log="${2:-}"
    local summary="${3:-}"
    local catalog rendered hold body
    ADVICE=""
    ADVICE_HOLD=0
    catalog="$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")/alert-advice.txt"
    [[ -f "${catalog}" ]] || return 0
    load_text "${G_LANGUAGE:-en}"
    rendered=""
    rendered="$(
        python3 - "${tool}" "${log}" "${summary}" "${catalog}" << 'PY'
#!/usr/bin/env python3
"""Render the false-positive advice for one AIDE, chkrootkit or rkhunter log."""

import os
import re
import shlex
import sys

KEY_RE = re.compile(r"^[a-z][a-z0-9-]*(?:\.[a-z0-9-]+)+$")
RECORD_RE = re.compile(r"^\[([a-z][a-z0-9-]*(?:\.[a-z0-9-]+)+)\]$")


def read_text_dir(directory, data):
    if not directory or not os.path.isdir(directory):
        return
    for name in sorted(os.listdir(directory)):
        if not name.endswith(".txt"):
            continue
        path = os.path.join(directory, name)
        if not os.path.isfile(path):
            continue
        key = ""
        value = []

        def store():
            nonlocal key, value
            if not key:
                return
            text = "\n".join(value)
            while text.endswith("\n"):
                text = text[:-1]
            data[key] = text

        with open(path, encoding="utf-8", errors="replace") as handle:
            for raw in handle:
                line = raw.rstrip("\n")
                match = RECORD_RE.match(line)
                if match:
                    store()
                    key = match.group(1)
                    value = []
                    continue
                if key:
                    value.append(line)
            store()


def load_dirs(spec):
    data = {}
    for directory in (spec or "").split(":"):
        if directory:
            read_text_dir(directory, data)
    return data


LANG_TEXT = load_dirs(os.environ.get("G_TEXT_LANG_DIRS", ""))
EN_TEXT = load_dirs(os.environ.get("G_TEXT_EN_DIRS", ""))


def text_get(key):
    chosen = LANG_TEXT.get(key)
    if chosen:
        return chosen
    chosen = EN_TEXT.get(key)
    if chosen:
        return chosen
    return key


def apply_text(text, *args):
    def repl(match):
        num = int(match.group(1))
        if 1 <= num <= len(args):
            return str(args[num - 1])
        return match.group(0)

    return re.sub(r"\{(\d+)\}", repl, text)


def resolve(value):
    if not value or "\n" in value:
        return value or ""
    if KEY_RE.match(value):
        return text_get(value)
    return value

LATE = {
    "aide.removed",
    "aide.package",
    "aide.conffile",
    "aide.unknown",
    "chk.unknown",
    "rk.unknown",
}
UNKNOWN = {
    "aide": "aide.unknown",
    "chkrootkit": "chk.unknown",
    "rkhunter": "rk.unknown",
}
LOOP_VARS = {
    "paths": "p",
    "cmds": "c",
    "pids": "pid",
    "bins": "b",
    "ports": "port",
    "ifaces": "iface",
}
BINARIES = {
    "amd", "basename", "biff", "chfn", "chsh", "cron", "date", "du", "dirname",
    "echo", "egrep", "env", "find", "fingerd", "gpm", "grep", "hdparm", "su",
    "ifconfig", "inetd", "identd", "init", "killall", "login", "ls", "lsof",
    "mail", "mingetty", "netstat", "named", "passwd", "pidof", "pop2", "pop3",
    "ps", "pstree", "rpcinfo", "rlogind", "rshd", "slogin", "sendmail", "sshd",
    "syslogd", "tar", "tcpd", "tcpdump", "top", "telnetd", "timed", "traceroute",
    "vdir", "w", "write",
}
APP_PAIRS = (
    ("openssh", "openssh-server"),
    ("openssl", "openssl"),
    ("exim", "exim4"),
    ("apache", "apache2"),
    ("nginx", "nginx"),
    ("proftpd", "proftpd-basic"),
    ("vsftpd", "vsftpd"),
    ("sendmail", "sendmail"),
    ("bind9", "bind9"),
    ("named", "bind9"),
    ("ssh", "openssh-server"),
)
AIDE_ENTRY = re.compile(
    r"^(?:[fdlcbpsDP!?][+.\-:=> <?A-Za-z]*:\s+\S|(?:added|removed|changed):\s+\S)"
)
AIDE_HEAD = re.compile(
    r"^(?:file|directory|fifo|link|block device|character device|"
    r"socket|door|port|unknown file type):\s+\S",
    re.I,
)
AIDE_DIFF = re.compile(r"^entry \S+ in databases has different attributes\b", re.I)
AIDE_DB = re.compile(r"^the attributes of the \(uncompressed\) database\b", re.I)
AIDE_PATH = re.compile(
    r"^(?:[fdlcbpsDP!?][+.\-:=> <?A-Za-z]*|(?:added|removed|changed)|"
    r"(?:File|Directory|FIFO|Link|Block device|Character device|Socket|Door|Port|"
    r"Unknown file type)):\s+(\S.*)$",
    re.I,
)
AIDE_ENTRY_PATH = re.compile(
    r"^Entry (\S+) in databases has different attributes\b",
    re.I,
)
REMOVED_LINE = re.compile(r"^(?:removed:\s+\S|[fdlcbpsDP!?][-]{3,}:\s+\S)")
PATH_TOKEN = re.compile(
    r"(?<![A-Za-z0-9])(/(?:[\w.+@=-]|\\x[0-9A-Fa-f]{2})+"
    r"(?:/(?:[\w.+@=-]|\\x[0-9A-Fa-f]{2})+)*)"
)


class Finding:
    def __init__(self, lines, paths):
        self.lines = lines
        self.paths = paths


def parse_catalog(text):
    records = []
    current = None
    mode = None
    buf = []

    def flush_mode():
        nonlocal mode, buf
        if current is not None and mode:
            current[mode] = "\n".join(buf).strip("\n")
        mode = None
        buf = []

    for raw in text.splitlines():
        if mode:
            if raw == mode + ">>":
                flush_mode()
            else:
                buf.append(raw)
            continue
        if not raw.strip() or raw.startswith("#"):
            continue
        if raw.startswith("[") and raw.endswith("]"):
            if current:
                records.append(current)
            current = {"id": raw[1:-1]}
            continue
        if current is None:
            continue
        if raw.endswith("<<"):
            mode = raw[: -2]
            buf = []
            continue
        if "=" in raw:
            key, value = raw.split("=", 1)
            current[key.strip()] = value.strip()
    if current:
        records.append(current)
    for rec in records:
        rec["regex"] = re.compile(rec.get("match") or r"$^")
        rec["hold"] = rec.get("hold", "0")
        if rec.get("hold_if"):
            rec["hold_re"] = re.compile(rec["hold_if"])
        else:
            rec["hold_re"] = None
    return records


def normalize_tool(tool):
    key = (tool or "").strip().lower()
    if key in {"aide", "chkrootkit", "rkhunter"}:
        return key
    return ""


def aide_path(line):
    stripped = line.strip()
    match = AIDE_ENTRY_PATH.match(stripped)
    if match:
        return match.group(1).strip()
    match = AIDE_PATH.match(stripped)
    if match:
        return match.group(1).strip()
    return ""


def aide_findings(text):
    findings = []
    for raw in text.splitlines():
        line = raw.rstrip()
        stripped = line.strip()
        if not stripped:
            continue
        if AIDE_DB.match(stripped):
            break
        if line[:1] in (" ", "\t"):
            continue
        if not (AIDE_ENTRY.match(line) or AIDE_HEAD.match(stripped) or AIDE_DIFF.match(stripped)):
            continue
        path = aide_path(line)
        findings.append(Finding([line], [path] if path else []))
    return findings


def is_noise(line):
    stripped = line.strip()
    if re.match(r"^\d{4}-\d{2}-\d{2}T", stripped):
        return True
    if re.search(r"Rootkit Hunter version", stripped, re.I):
        return True
    if re.search(r"\[ (?:OK|Not found|None found|Skipped) \]", stripped):
        return True
    if re.match(
        r"(?i)^(start timestamp|end timestamp|summary:|total number of|"
        r"added entries|removed entries|changed entries|detailed information|"
        r"aide found|looking for|checking rkhunter data)",
        stripped,
    ):
        return True
    return False


def is_header(tool, line):
    stripped = line.strip()
    if tool == "chkrootkit":
        return bool(
            re.search(
                r"(?i)(INFECTED|PACKET SNIFFER|ifpromisc|deletion|"
                r"ld\.so\.preload|bpfdoor|haldrund|Checking\s+[`'\"]|"
                r"bindshell|wtmp|lastlog|\butmp\b|hidden|PROMISC)",
                stripped,
            )
        )
    return bool(
        re.search(
            r"(?i)(^warning:|replaced by a script|possible rootkit|promiscuous|"
            r"packet sniffer|hidden (?:file|directory|process)|uid of 0|"
            r"no password|empty password|mirrors\.dat modifié|startup file|"
            r"world-writable|world writable|immutable|deleted|listening port|"
            r"hidden port|ld\.so\.preload|\binetd\b|suspect|out of date|"
            r"rootkit|trojan|malware)",
            stripped,
        )
    )


def is_cont(line):
    if line[:1] in (" ", "\t"):
        return True
    stripped = line.strip()
    if stripped.startswith("/"):
        return True
    if re.match(r"(?i)^file:\s+\S", stripped):
        return True
    if re.match(r"(?i)^INFECTED\b", stripped):
        return True
    return False


def looks_like(line):
    stripped = line.strip()
    if stripped.startswith("/"):
        return True
    return bool(re.search(r"(?i)INFECTED|^warning:", stripped))


def extract_paths(text):
    found = []
    for line in text.splitlines():
        match = re.match(r"^\s*(?:File|Directory|Link):\s+(\S.*)$", line, re.I)
        if match:
            path = match.group(1).strip()
            if path not in found:
                found.append(path)
            continue
        for path in PATH_TOKEN.findall(line):
            if path.startswith("/proc/"):
                continue
            if path not in found:
                found.append(path)
    return found


def other_findings(tool, text):
    findings = []
    current = None

    def flush():
        nonlocal current
        if not current:
            return
        paths = extract_paths("\n".join(current))
        findings.append(Finding(current, paths))
        current = None

    for raw in text.splitlines():
        line = raw.rstrip()
        if not line.strip():
            flush()
            continue
        if is_noise(line):
            continue
        if current is not None and is_cont(line):
            current.append(line)
            continue
        if is_header(tool, line) or looks_like(line):
            flush()
            current = [line]
            continue
    flush()
    return findings


def is_pkg_path(path):
    return bool(re.match(r"^/(?:bin|sbin|usr|lib|lib64|boot)(?:/|$)", path or ""))


def is_etc_path(path):
    return path == "/etc" or (path or "").startswith("/etc/")


def quote_join(values, limit=40):
    shown = list(values)[:limit]
    return " ".join(shlex.quote(value) for value in shown)


def drop_empty_loops(script, present):
    for token, var in LOOP_VARS.items():
        if present.get(token):
            continue
        script = re.sub(
            rf"for {var} in \{{{token}\}}; do\n.*?^done\n?",
            "",
            script,
            flags=re.S | re.M,
        )
        script = script.replace("{" + token + "}", "")
    return script


def apply_tokens(script, present):
    script = drop_empty_loops(script, present)
    for token, value in present.items():
        if value:
            script = script.replace("{" + token + "}", value)
    if not present.get("raw_lines"):
        script = re.sub(r"^printf '%s\\n' \{raw_lines\}\n?", "", script, flags=re.M)
        script = script.replace("{raw_lines}", "")
    else:
        script = script.replace("{raw_lines}", present["raw_lines"])
    script = re.sub(r"sudo bash << 'EOF'\n\s*EOF\n?", "", script)
    script = re.sub(r"\n{3,}", "\n\n", script)
    return script.strip()


def extract_cmds(text):
    found = []
    for name in re.findall(r"Checking\s+[`'\"]([A-Za-z0-9_.+-]+)[`'\"]", text):
        if name in BINARIES and name not in found:
            found.append(name)
    return found


def extract_pids(text):
    found = []
    patterns = (
        r"(?i)\bpid[=: ]+(\d+)",
        r"\[(\d+)\]",
        r"/proc/(\d+)\b",
        r"(?i)\bprocess(?: id)?[=: ]+(\d+)",
    )
    for pattern in patterns:
        for number in re.findall(pattern, text):
            if number != "0" and number not in found:
                found.append(number)
    return found


def extract_ports(text):
    found = []
    for number in re.findall(r"(?i)ports?\D{0,16}(\d{1,5})\b", text):
        if number != "0" and number not in found:
            found.append(number)
    return found


def extract_ifaces(text):
    found = []
    pattern = (
        r"\b((?:docker0|virbr\d+|veth[A-Za-z0-9]+|br-[A-Za-z0-9]+|"
        r"tun\d+|tap\d+|wg\d+|tailscale\d+|"
        r"en(?:o|p|s|x)[A-Za-z0-9]+|wl[a-z]*\d+[A-Za-z0-9]*|eth\d+))\b"
    )
    for name in re.findall(pattern, text):
        if name not in found:
            found.append(name)
    return found


def extract_bins(text):
    found = []
    for path in re.findall(r"\((/[^()\s]+)\[\d+\]\)", text):
        if path not in found:
            found.append(path)
    return found


def extract_pkgs(text):
    found = []
    lower = text.lower()
    for needle, package in APP_PAIRS:
        if needle in lower and package not in found:
            found.append(package)
    if not found:
        found = ["openssh-server", "openssl"]
    return found


def build_snap(paths):
    files = []
    snaps = []
    for path in paths:
        base = os.path.basename(path)
        match = re.search(r"(snap-.+\.mount)$", base)
        if not match:
            continue
        filename = match.group(1)
        if filename not in files:
            files.append(filename)
        decoded = re.sub(r"(?i)\\x2d", "-", filename)
        name_match = re.match(r"snap-(.+)-(\d+)\.mount$", decoded)
        snap = name_match.group(1) if name_match else ""
        if snap and snap not in snaps:
            snaps.append(snap)
    lines = []
    chosen = files
    if not chosen:
        chosen = [os.path.basename(path) for path in paths if path]
    for filename in chosen:
        lines.append(
            "sudo find /etc/systemd/system -name "
            + shlex.quote(filename)
            + " -printf '%y %m %u:%g %p\\n'"
        )
    if snaps:
        for snap in snaps:
            lines.append("snap info " + shlex.quote(snap))
    else:
        lines.append("echo " + shlex.quote(text_get("alert.snap.unrecognized")))
    lines.append("snap changes")
    return "\n".join(lines)


def command_for(rec, paths, raw_lines, text):
    kind = rec.get("kind") or ""
    if kind == "snap" or rec["id"] == "aide.snap-mount":
        return build_snap(paths)
    present = {
        "paths": quote_join(paths),
        "cmds": quote_join(extract_cmds(text)),
        "pids": quote_join(extract_pids(text)),
        "bins": quote_join(extract_bins(text) or [path for path in paths if not path.endswith("/")]),
        "ports": quote_join(extract_ports(text)),
        "ifaces": quote_join(extract_ifaces(text)),
        "pkgs": quote_join(extract_pkgs(text) if kind == "apps" or "{pkgs}" in rec.get("command", "") else []),
        "raw_lines": quote_join(raw_lines),
    }
    # bins should stay empty when the template has no real binary path.
    if not extract_bins(text):
        present["bins"] = ""
    if kind != "apps" and "{pkgs}" not in rec.get("command", ""):
        present["pkgs"] = ""
    script = apply_tokens(rec.get("command", ""), present)
    if kind == "promisc" and "for iface in" not in script:
        extra = "ip -d link show"
        script = (script + "\n" + extra).strip() if script else extra
    if re.search(r"\{[a-z_]+\}", script):
        script = script + "\necho " + shlex.quote(text_get("alert.command.missing"))
    return script.strip()


def classify(tool, findings, records):
    by_id = {rec["id"]: rec for rec in records}
    specific = [
        rec for rec in records if rec.get("tool") == tool and rec["id"] not in LATE
    ]
    groups = {}
    order = []
    assigned = {}

    def take(rec, finding):
        gid = rec["id"]
        if gid not in groups:
            groups[gid] = {"rec": rec, "lines": [], "paths": []}
            order.append(gid)
        group = groups[gid]
        for line in finding.lines:
            if line not in group["lines"]:
                group["lines"].append(line)
        for path in finding.paths:
            if path and path not in group["paths"]:
                group["paths"].append(path)
                assigned[path] = gid

    for finding in findings:
        owner = None
        for path in finding.paths:
            if path in assigned:
                owner = assigned[path]
                break
        if owner:
            take(by_id[owner], finding)
            continue
        text = "\n".join(finding.lines)
        chosen = None
        for rec in specific:
            if rec["regex"].search(text):
                chosen = rec
                break
        if chosen is None and tool == "aide" and finding.lines and REMOVED_LINE.match(finding.lines[0].strip()):
            chosen = by_id.get("aide.removed")
        if (
            chosen is None
            and tool == "aide"
            and finding.paths
            and is_pkg_path(finding.paths[0])
        ):
            chosen = by_id.get("aide.package")
        if (
            chosen is None
            and tool == "aide"
            and finding.paths
            and is_etc_path(finding.paths[0])
        ):
            chosen = by_id.get("aide.conffile")
        if chosen is None:
            chosen = by_id.get(UNKNOWN[tool])
        if chosen is None:
            continue
        take(chosen, finding)
    return [groups[gid] for gid in order]


def section(group):
    rec = group["rec"]
    lines = group["lines"]
    shown = lines[:40]
    hidden = len(lines) - len(shown)
    text = "\n".join(lines)
    command = command_for(rec, group["paths"], shown, text)
    parts = [resolve(rec.get("title")) or rec["id"]]
    notice = resolve(rec.get("notice"))
    if notice:
        parts.append(notice)
    parts.append(text_get("alert.label.lines"))
    parts.extend(shown)
    if hidden:
        parts.append(apply_text(text_get("alert.label.more"), hidden))
    parts.append("")
    parts.append(text_get("alert.label.command"))
    parts.append(command)
    parts.append("")
    parts.append(text_get("alert.label.benign"))
    parts.append(resolve(rec.get("benign", "")))
    parts.append("")
    parts.append(text_get("alert.label.malicious"))
    parts.append(resolve(rec.get("malicious", "")))
    return "\n".join(parts).rstrip()


def hold_of(groups):
    for group in groups:
        rec = group["rec"]
        if rec.get("hold") == "1":
            return 1
        if rec.get("hold_re") and rec["hold_re"].search("\n".join(group["lines"])):
            return 1
    return 0


def render(tool, log_text, summary, catalog_text):
    tool = normalize_tool(tool)
    if not tool:
        return "", 0
    if re.search(
        r"planté|crashed|abgestürzt|bloqueó|erreur rc=|error rc=|Fehler rc=|"
        r"n'est pas allé au bout|did not finish|nicht zu Ende|no llegó al final",
        summary or "",
        re.I,
    ):
        return "", 0
    records = parse_catalog(catalog_text)
    body = log_text or ""
    for mark in (
        "mirrors.dat modifié hors",
        "mirrors.dat changed outside",
        "mirrors.dat geändert außerhalb",
        "mirrors.dat modificado fuera",
    ):
        if summary and mark in summary and mark not in body:
            body = summary + "\n" + body
            break
    if tool == "aide":
        findings = aide_findings(body)
    else:
        findings = other_findings(tool, body)
    if not findings:
        return "", 0
    groups = classify(tool, findings, records)
    if not groups:
        return "", 0
    advice = "\n\n".join(section(group) for group in groups)
    return advice, hold_of(groups)


def main():
    tool = sys.argv[1] if len(sys.argv) > 1 else ""
    log_path = sys.argv[2] if len(sys.argv) > 2 else ""
    summary = sys.argv[3] if len(sys.argv) > 3 else ""
    catalog_path = sys.argv[4] if len(sys.argv) > 4 else ""
    log_text = ""
    if log_path and os.path.isfile(log_path):
        with open(log_path, encoding="utf-8", errors="replace") as handle:
            log_text = handle.read()
    with open(catalog_path, encoding="utf-8") as handle:
        catalog_text = handle.read()
    advice, hold = render(tool, log_text, summary, catalog_text)
    sys.stdout.write(f"HOLD={hold}\n---\n")
    if advice:
        sys.stdout.write(advice)
        if not advice.endswith("\n"):
            sys.stdout.write("\n")


if __name__ == "__main__":
    main()
PY
    )" || rendered=""
    hold="${rendered%%$'\n'*}"
    body="${rendered#*$'\n'}"
    case "${body}" in
        ---) body="" ;;
        ---$'\n'*) body="${body#---$'\n'}" ;;
    esac
    case "${hold}" in
        HOLD=1) ADVICE_HOLD=1 ;;
        *) ADVICE_HOLD=0 ;;
    esac
    ADVICE="${body}"
    return 0
}

write_alert_file() {
    local alert="$1" summary="$2" excerpt="$3" advice="$4" note="$5" note_cmd="$6"
    local dir
    [[ -n "${alert}" ]] || return 0
    dir="$(dirname -- "${alert}")"
    mkdir -p "${dir}" 2>/dev/null || true
    {
        printf '%s\n' "${summary}"
        if [[ -n "${excerpt}" ]]; then
            printf '\n%s\n' "${excerpt}"
        fi
        if [[ -n "${advice}" ]]; then
            printf '\n%s\n' "${advice}"
        fi
        if [[ -n "${note}" ]]; then
            printf '\n%s\n' "${note}"
        fi
        if [[ -n "${note_cmd}" ]]; then
            printf '\n%s\n' "${note_cmd}"
        fi
    } > "${alert}" || true
}

copy_alert_drive() {
    local alert="${1:-}"
    local base remote path config
    [[ "${G_RCLONE_ALERTS:-0}" == "1" ]] || return 0
    [[ -n "${alert}" && -f "${alert}" ]] || return 0
    base="$(get_product_base)"
    remote="${G_RCLONE_REMOTE:-}"
    path="${G_RCLONE_PATH:-}"
    config="${base}/cron/rclone.conf"
    if [[ -z "${remote}" || -z "${path}" || ! -f "${config}" ]]; then
        printf '%s\n' "$(get_text watchdog.copy-drive-ignored)" >&2
        return 0
    fi
    if ! command -v rclone >/dev/null 2>&1; then
        printf '%s\n' "$(get_text watchdog.copy-drive-ignored-rclone-absent)" >&2
        return 0
    fi
    if ! RCLONE_CONFIG="${config}" rclone copy "${alert}" "${remote}:${path}" >/dev/null 2>&1; then
        printf '%s\n' "$(get_text watchdog.copy-drive-rejected-the-file-local-is-kept)" >&2
    fi
    return 0
}

log_alert() {
    local summary="$*"
    local excerpt="" module log alert line send base note="" note_cmd="" tool=""
    local hold_note="$(get_text alert.hold.note)"
    log="${LOG_FILE:-${LOG:-}}"
    alert="${ALERT_FILE:-}"
    excerpt="$(get_alert_excerpt "${log}")"
    line="$(printf '%s %s' "$(date -Iseconds)" "${summary}")"
    if [[ -n "${log}" ]]; then
        printf '%s\n' "${line}" | tee -a "${log}"
    else
        printf '%s\n' "${line}"
    fi
    module="${MODULE_NAME:-}"
    if [[ -z "${module}" && -n "${log}" ]]; then
        module="$(basename "${log}" | sed -E 's/-[0-9]{8}-.*//')"
    fi
    module="${module:-$(get_text alert.module.fallback)}"
    base="$(get_product_base)"
    ADVICE=""
    ADVICE_HOLD=0
    if take_quarantine_note; then
        note=""
        note_cmd=""
        ADVICE=""
        ADVICE_HOLD=0
    else
        if [[ "${W_AIDE_REFRESH:-}" == "1" ]]; then
            note="$(get_text alert.note.aide)"
            note_cmd="sudo bash ${base}/bin/aide-refresh-db.sh"
        elif [[ "${W_RKHUNTER_REFRESH:-}" == "1" ]]; then
            prepare_rkhunter_note
            note="${NOTE}"
            note_cmd="${NOTE_CMD}"
        elif [[ "${W_CHKROOTKIT_IGNORE:-}" == "1" && -n "${log}" ]]; then
            note="$(get_text alert.note.chkrootkit)"
            note_cmd="sudo bash ${base}/bin/chkrootkit-ignore-log.sh '${log}'"
        elif [[ "${W_DEBSUMS_IGNORE:-}" == "1" && -n "${log}" ]]; then
            note="$(get_text alert.note.debsums)"
            note_cmd="sudo bash ${base}/bin/debsums-ignore-log.sh '${log}'"
        fi
        if tool="$(get_alert_tool "${module}" "${log}" "${summary}")"; then
            render_alert_advice "${tool}" "${log}" "${summary}"
            if [[ "${ADVICE_HOLD:-0}" == "1" && -n "${note_cmd}" ]]; then
                note="${hold_note}"
            fi
        fi
    fi
    if [[ -z "${NOTE:-}" && -n "${note}" ]]; then
        NOTE="${note}"
        NOTE_CMD="${note_cmd}"
    fi
    if [[ "${ADVICE_HOLD:-0}" == "1" && -n "${NOTE_CMD:-}" ]]; then
        NOTE="${hold_note}"
    fi
    if [[ -z "${TITLE:-}" ]]; then
        TITLE="$(get_text alert.title.module "${module}")"
    fi
    if [[ -z "${G_PROJECT_NAME:-}" ]]; then
        if [[ -n "${W_BASE:-}" ]]; then
            G_PROJECT_NAME="Liltress Workstation"
        else
            G_PROJECT_NAME="Liltress"
        fi
    fi
    write_alert_file "${alert}" "${summary}" "${excerpt}" "${ADVICE:-}" "${NOTE:-}" "${NOTE_CMD:-}"
    if [[ "${G_MAIL_ALERTS:-0}" == "1" && -n "${G_WATCHDOG_MAIL:-}" ]]; then
        send="$(send_path)" || true
        if [[ -n "${send}" ]]; then
            TITLE="${TITLE}" \
            MODULE_NAME="${module}" \
            CONTENT="${summary}

${excerpt}" \
            NOTE="${NOTE:-}" \
            NOTE_CMD="${NOTE_CMD:-}" \
            ADVICE="${ADVICE:-}" \
            G_WATCHDOG_MAIL="${G_WATCHDOG_MAIL}" \
            G_PROJECT_NAME="${G_PROJECT_NAME}" \
            G_MAIL_TEMPLATE="${G_MAIL_TEMPLATE:-mail.html}" \
                bash "${send}" || true
        fi
    fi
    copy_alert_drive "${alert}" || true
}

report_clamav() {
    local crashed=0 signal phrase log
    log="${LOG_FILE:-${LOG:-}}"
    [[ -n "${log}" && -f "${log}" ]] || return 1
    crashed="$(grep -c 'planté signal .* sur ' "${log}" || true)"
    [[ "${crashed}" -gt 0 ]] || return 1
    signal="$(sed -n 's/.*planté signal \([0-9][0-9]*\).*/\1/p' "${log}" | head -n 1)"
    phrase="$(signal_phrase "${signal}")"
    if grep -q 'contrôle arrêté' "${log}"; then
        log_alert "$(get_text watchdog.clamav-crashed-twice-in-a-row-signal-the-check-s "${signal}" "${phrase}")"
    elif [[ "${crashed}" -eq 1 ]]; then
        log_alert "$(get_text watchdog.clamav-crashed-signal-on-one-file-that-file-was "${signal}" "${phrase}")"
    else
        log_alert "$(get_text watchdog.clamav-crashed-signal-on-files-those-files-were "${signal}" "${phrase}" "${crashed}")"
    fi
    return 0
}

render_mail_about() {
    case "${MODULE_NAME:-}" in
        Aide) printf '%s\n' "$(get_text log.integrity-of-the-files-watched-by-help-help-chec)" ;;
        Chkrootkit) printf '%s\n' "$(get_text watchdog.about.chkrootkit)" ;;
        Rkhunter) printf '%s\n' "$(get_text log.search-of-rootkits-and-files-changed-rkhunter-ch)" ;;
        Clamav) printf '%s\n' "$(get_text log.files-reported-by-clamav-quarantine-and-journals)" ;;
        Auditd) printf '%s\n' "$(get_text log.events-of-audit-abnormal-ausearch)" ;;
        Debsums) printf '%s\n' "$(get_text log.files-of-packages-whose-the-checksum-a-changed-d)" ;;
        Fail2ban) printf '%s\n' "$(get_text log.bans-fail2ban-of-the-derni-res-24-h)" ;;
        Crowdsec) printf '%s\n' "$(get_text log.decisions-and-alerts-crowdsec-of-the-derni-res-2)" ;;
        Ufw) printf '%s\n' "$(get_text log.packages-blocked-by-ufw)" ;;
        Reboot) printf '%s\n' "$(get_text watchdog.a-restart-is-useful-the-machine-was-not-restarte)" ;;
        *) printf '%s\n' "$(get_text watchdog.about.module "${MODULE_NAME:-$(get_text watchdog.module.unknown)}")" ;;
    esac
}

deliver_mail() {
    local script_dir detail _mail_sh _candidate tpl
    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[1]}")" && pwd)"
    detail="$(printf '%s' "${CONTENT:-}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [[ -z "${detail}" ]]; then
        echo "$(get_text watchdog.mail-not-sent-empty-body "${MODULE_NAME:-?}")" >&2
        exit 0
    fi
    if [[ "${G_MAIL_ABOUT:-0}" == "1" ]]; then
        CONTENT="$(render_mail_about)

${detail}"
    else
        CONTENT="${detail}"
    fi
    HOSTNAME="$(hostname -s 2>/dev/null || hostname)"
    DATE="${DATE:-$(date '+%Y-%m-%d %H:%M:%S')}"
    TITLE="${TITLE:-$(get_text alert.title.short)}"
    MODULE_NAME="${MODULE_NAME:-$(get_text alert.module.mail)}"
    if [[ -z "${G_PROJECT_NAME:-}" ]]; then
        if [[ -n "${W_BASE:-}" ]]; then
            G_PROJECT_NAME="Liltress Workstation"
        else
            G_PROJECT_NAME="Liltress"
        fi
    fi
    export TITLE G_PROJECT_NAME HOSTNAME DATE MODULE_NAME CONTENT
    export NOTE="${NOTE:-}"
    export NOTE_CMD="${NOTE_CMD:-}"
    export ADVICE="${ADVICE:-}"
    _mail_sh=""
    for _candidate in \
        "${script_dir}/mail.sh" \
        "${G_CONFIG_BASE_DIRECTORY:-}/cron/bin/mail.sh" \
        "${G_CONFIG_BASE_DIRECTORY:-}/src/core/mail.sh" \
        "${G_INSTALL_DIRECTORY:-}/core/mail.sh" \
        "${G_INSTALL_DIRECTORY:-}/../core/mail.sh" \
        "${script_dir}/../../../core/mail.sh" \
        "${script_dir}/../../../../core/mail.sh" \
        "${script_dir}/../core/mail.sh" \
        "${script_dir}/../../core/mail.sh" \
        "${script_dir}/../../src/core/mail.sh"
    do
        if [[ -n "${_candidate}" && -f "${_candidate}" ]]; then
            _mail_sh="${_candidate}"
            break
        fi
    done
    if [[ -z "${_mail_sh}" ]]; then
        echo "$(get_text watchdog.mail-not-sent-core-mail-sh-not-found "${MODULE_NAME}")" >&2
        exit 0
    fi
    # shellcheck disable=SC1090
    source "${_mail_sh}"
    tpl="$(locate_mail_template "${script_dir}")" || {
        echo "$(get_text watchdog.mail-not-sent-template-html-not-found "${MODULE_NAME}")" >&2
        exit 0
    }
    if [[ "${G_MAIL_REDACT:-0}" == "1" ]]; then
        if ! MAIL_CONTENT="$(G_MAIL_REDACT=1 render_mail "${tpl}")"; then
            echo "$(get_text watchdog.mail-not-sent-template-html-invalid "${MODULE_NAME}")" >&2
            exit 0
        fi
    elif ! MAIL_CONTENT="$(render_mail "${tpl}")"; then
        echo "$(get_text watchdog.mail-not-sent-template-html-invalid "${MODULE_NAME}")" >&2
        exit 0
    fi
    if [[ -n "${HTML_REPORT:-}" ]]; then
        printf '%s\n' "${MAIL_CONTENT}" > "${HTML_REPORT}" || true
        copy_alert_drive "${HTML_REPORT}" || true
    fi
    if [[ "${G_MAIL_REQUIRE_FLAG:-0}" == "1" ]]; then
        if [[ "${G_MAIL_ALERTS:-0}" != "1" || -z "${G_WATCHDOG_MAIL:-}" ]]; then
            echo "$(get_text watchdog.mail-not-sent-alerts-e-mail-off "${MODULE_NAME:-?}")" >&2
            exit 0
        fi
    elif [[ -z "${G_WATCHDOG_MAIL:-}" ]]; then
        echo "$(get_text watchdog.mail-not-sent-destinataire-or-empty-body "${MODULE_NAME:-?}")" >&2
        exit 0
    fi
    if ! command -v mail >/dev/null 2>&1; then
        echo "$(get_text watchdog.mail-not-sent-command-mail-absent "${MODULE_NAME:-?}")" >&2
        exit 0
    fi
    printf '%s\n' "${MAIL_CONTENT}" | mail -s "${G_PROJECT_NAME} - ${HOSTNAME} - ${MODULE_NAME}" \
        -a "Content-Type: text/html; charset=UTF-8" \
        "${G_WATCHDOG_MAIL}"
}
