#!/usr/bin/env bash
# =============================================================================
# File       : core/mail.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

check_mail_template_name() {
    [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.html$ ]]
}

log_mail_fatal() {
    if declare -F log_error >/dev/null 2>&1; then
        log_error "${INSTALL_WATCHER:-BASH}" "install.mail.error" "$*"
    fi
    printf '%s\n' "$*" >&2
    exit 1
}

install_mail_templates() {
    local dest="$1"
    local src="${G_INSTALL_DIRECTORY:?}/template"
    local chosen="${G_MAIL_TEMPLATE:-mail.html}"
    local f base n=0
    local nullglob_was=0
    [[ -d "${dest}" ]] || log_mail_fatal "$(get_text mail.directory-of-installation-of-the-mod-les-absent "${dest}")"
    [[ -d "${src}" ]] || log_mail_fatal "$(get_text mail.directory-template-absent "${src}")"
    check_mail_template_name "${chosen}" || log_mail_fatal "$(get_text mail.g-mail-template-invalid-example-mail-html "${chosen}")"

    if shopt -q nullglob; then
        nullglob_was=1
    fi
    shopt -s nullglob
    for f in "${src}/"*.html; do
        base="$(basename -- "${f}")"
        check_mail_template_name "${base}" || log_mail_fatal "$(get_text mail.name-of-template-denied-example-mail-html "${base}")"
        cp -f -- "${f}" "${dest}/${base}"
        chmod 644 "${dest}/${base}"
        n=$((n + 1))
    done
    if [[ "${nullglob_was}" -eq 0 ]]; then
        shopt -u nullglob
    fi
    [[ "${n}" -ge 1 ]] || log_mail_fatal "$(get_text mail.no-file-html-in "${src}")"
    [[ -f "${dest}/${chosen}" ]] || log_mail_fatal "$(get_text mail.template-absent-of "${chosen}" "${src}")"
}

get_mail_name() {
    local here="${1:-}"
    local conf line
    local -a confs=()
    [[ -n "${G_INSTALL_DIRECTORY:-}" ]] && confs+=("${G_INSTALL_DIRECTORY}/config/global.conf")
    [[ -n "${G_CONFIG_BASE_DIRECTORY:-}" ]] && confs+=("${G_CONFIG_BASE_DIRECTORY}/src/config/global.conf")
    if [[ -n "${here}" ]]; then
        confs+=(
            "${here}/../../src/config/global.conf"
            "${here}/../../../config/global.conf"
            "${here}/../config/global.conf"
        )
    fi
    for conf in "${confs[@]}"; do
        [[ -f "${conf}" ]] || continue
        line="$(awk -F= '/^G_MAIL_TEMPLATE=/{gsub(/"/,"",$2); gsub(/[[:space:]]/,"",$2); print $2; exit}' "${conf}")"
        if [[ -n "${line}" ]]; then
            printf '%s\n' "${line}"
            return 0
        fi
    done
    if [[ -n "${G_MAIL_TEMPLATE:-}" ]]; then
        printf '%s\n' "${G_MAIL_TEMPLATE}"
        return 0
    fi
    printf '%s\n' "mail.html"
}

locate_mail_template() {
    local here="${1:-}"
    local name dir
    local -a dirs=()
    name="$(get_mail_name "${here}")"
    check_mail_template_name "${name}" || return 1
    [[ -n "${G_INSTALL_DIRECTORY:-}" ]] && dirs+=("${G_INSTALL_DIRECTORY}/template")
    [[ -n "${G_CONFIG_BASE_DIRECTORY:-}" ]] && dirs+=("${G_CONFIG_BASE_DIRECTORY}/src/template")
    if [[ -n "${here}" ]]; then
        dirs+=(
            "${here}/../../src/template"
            "${here}/../../../template"
            "${here}/../template"
            "${here}"
        )
    fi
    for dir in "${dirs[@]}"; do
        if [[ -f "${dir}/${name}" ]]; then
            printf '%s\n' "${dir}/${name}"
            return 0
        fi
    done
    return 1
}

render_mail() {
    local template="$1"
    local mail_here="" mail_candidate=""
    local mail_module="" mail_redacted="" mail_redacted_key="" mail_unreadable="" mail_no_pre=""
    [[ -f "${template}" ]] || return 1
    if ! declare -F get_text >/dev/null 2>&1; then
        mail_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
        for mail_candidate in \
            "${mail_here}/log.sh" \
            "${G_PRODUCT_ROOT:-}/core/log.sh" \
            "${G_INSTALL_DIRECTORY:-}/core/log.sh" \
            "${G_INSTALL_DIRECTORY:-}/src/core/log.sh"
        do
            if [[ -n "${mail_candidate}" && -f "${mail_candidate}" ]]; then
                # shellcheck disable=SC1090
                source "${mail_candidate}"
                break
            fi
        done
    fi
    if declare -F get_text >/dev/null 2>&1; then
        load_text "${G_LANGUAGE:-en}"
        mail_module="$(get_text mail.module)"
        mail_redacted="$(get_text mail.redacted)"
        mail_redacted_key="$(get_text mail.redacted-key)"
        mail_unreadable="$(get_text mail.template-unreadable)"
        mail_no_pre="$(get_text mail.template-no-pre)"
    else
        mail_module="Module:"
        mail_redacted="[redacted]"
        mail_redacted_key="[private key redacted]"
        mail_unreadable="unreadable template: {1}"
        mail_no_pre="template without a pre tag"
    fi
    G_MAIL_TEMPLATE_FILE="${template}" \
    G_MAIL_REDACT="${G_MAIL_REDACT:-0}" \
    MAIL_LANG="${G_LANGUAGE:-en}" \
    MAIL_MODULE="${mail_module}" \
    G_TEXT_REDACTED="${mail_redacted}" \
    G_TEXT_REDACTED_KEY="${mail_redacted_key}" \
    G_TEXT_TEMPLATE_UNREADABLE="${mail_unreadable}" \
    G_TEXT_TEMPLATE_NO_PRE="${mail_no_pre}" \
    python3 - << 'PY'
import html
import os
import re
import sys
from pathlib import Path

redacted = os.environ.get("G_TEXT_REDACTED") or "[redacted]"
redacted_key = os.environ.get("G_TEXT_REDACTED_KEY") or "[private key redacted]"
token = re.escape(redacted)

def redact(text):
    text = re.sub(
        r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----",
        lambda _match: redacted_key,
        text,
        flags=re.S,
    )
    text = re.sub(
        rf"(?i)\bbearer\s+(?!{token})\S+",
        lambda _match: "Bearer " + redacted,
        text,
    )
    text = re.sub(
        rf"(?i)\b(password|passwd|token|jeton|api[_-]?key|secret|authorization|private[_-]?key|clé privée|clef privée)\b(\s*[:=]\s*)(?!{token})\S+",
        lambda match: match.group(1) + match.group(2) + redacted,
        text,
    )
    return text

redact_on = os.environ.get("G_MAIL_REDACT", "0") == "1"
content = os.environ.get("CONTENT", "")
note = os.environ.get("NOTE", "")
advice = os.environ.get("ADVICE", "")
if redact_on:
    content = redact(content)
    note = redact(note)
    advice = redact(advice)
note = note.strip()
advice = advice.strip()
note_cmd = os.environ.get("NOTE_CMD", "").strip()
path = Path(os.environ["G_MAIL_TEMPLATE_FILE"])
try:
    tpl = path.read_text(encoding="utf-8")
except OSError as exc:
    unread = os.environ.get("G_TEXT_TEMPLATE_UNREADABLE") or "unreadable template: {1}"
    print(unread.replace("{1}", str(exc)), file=sys.stderr)
    sys.exit(1)
for key in ("TITLE", "G_PROJECT_NAME", "HOSTNAME", "DATE", "MODULE_NAME", "MAIL_LANG", "MAIL_MODULE"):
    tpl = tpl.replace("${" + key + "}", html.escape(os.environ.get(key, ""), quote=False))
tpl = tpl.replace("${CONTENT}", html.escape(content, quote=False))
if advice:
    tpl = tpl.replace("${ADVICE}", html.escape(advice, quote=False))
else:
    tpl = re.sub(r"<!--ADVICE_START-->.*?<!--ADVICE_END-->", "", tpl, count=1, flags=re.S)
if note and note_cmd:
    tpl = tpl.replace("${NOTE}", html.escape(note, quote=False))
    tpl = tpl.replace("${NOTE_CMD}", html.escape(note_cmd, quote=False))
else:
    tpl = re.sub(r"<!--NOTE_START-->.*?<!--NOTE_END-->", "", tpl, count=1, flags=re.S)
if "<pre" not in tpl:
    missing_pre = os.environ.get("G_TEXT_TEMPLATE_NO_PRE") or "template without a pre tag"
    print(missing_pre, file=sys.stderr)
    sys.exit(1)
sys.stdout.write(tpl)
PY
}
