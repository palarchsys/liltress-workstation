#!/usr/bin/env python3
# =============================================================================
# File       : python/mail-render.py
# Updated at : 2026-11-14
# Creator    : palarchsys
# =============================================================================

import html
import os
import re
import sys
from pathlib import Path

import text_redact

redacted = os.environ.get("TEXT_REDACTED") or "[redacted]"
redacted_key = os.environ.get("TEXT_REDACTED_KEY") or "[private key redacted]"
token = re.escape(redacted)

def redact(text):
    return text_redact.redact_mail(text, redacted, redacted_key)

redact_on = os.environ.get("MAIL_REDACT", "0") == "1"
content = os.environ.get("CONTENT", "")
note = os.environ.get("NOTE", "")
advice = os.environ.get("ADVICE", "")
services = os.environ.get("MAIL_SERVICES", "")
files_block = os.environ.get("MAIL_FILES", "")
actions = os.environ.get("MAIL_ACTIONS", "")
if redact_on:
    content = redact(content)
    note = redact(note)
    advice = redact(advice)
    services = redact(services)
    files_block = redact(files_block)
    actions = redact(actions)
os.environ["MAIL_SERVICES"] = services
os.environ["MAIL_FILES"] = files_block
os.environ["MAIL_ACTIONS"] = actions
note = note.strip()
advice = advice.strip()
note_cmd = os.environ.get("NOTE_CMD", "").strip()

def advice_parts(text):
    blocks = []
    title = None
    lines = []
    marked = False

    def flush():
        nonlocal title, lines
        body = "\n".join(lines).strip()
        if title is not None or body:
            blocks.append((title, body))
        title = None
        lines = []

    for line in text.splitlines():
        if line.startswith("@@H@@"):
            marked = True
            flush()
            title = line[5:].strip()
            lines = []
        elif line.strip() == "@@BLOCK@@":
            marked = True
            flush()
        else:
            lines.append(line)
    flush()
    return marked, blocks

def advice_plain(text):
    marked, blocks = advice_parts(text)
    if not marked:
        return text
    out = []
    for title, body in blocks:
        if title:
            if out and out[-1] != "":
                out.append("")
            out.append(title)
        if body:
            out.append(body)
    return "\n".join(out).strip()

def mail_heading(text):
    return (
        '<div style="margin:0;padding:12px 16px 4px;font-size:16px;line-height:1.4;'
        'color:#e5b684;font-family:Arial,Helvetica,sans-serif;">'
        + html.escape(text, quote=False)
        + "</div>"
    )

def mail_pre(text, gap=False):
    margin = "0 0 16px" if gap else "0"
    return (
        '<pre style="margin:' + margin + ';width:100%;max-width:100%;box-sizing:border-box;'
        'display:block;background-color:#1e1e1e;padding:4px 16px 14px;color:#cccccc;'
        'font-family:Consolas,Courier New,monospace;font-size:13px;line-height:1.45;'
        'white-space:pre-wrap;word-wrap:break-word;word-break:break-word;'
        'overflow-wrap:break-word;overflow-x:auto;">'
        + html.escape(text, quote=False)
        + "</pre>"
    )

def advice_html(text):
    marked, blocks = advice_parts(text)
    if not marked:
        return mail_pre(text)
    pieces = []
    for title, body in blocks:
        if title:
            pieces.append(("h", title))
        if body:
            pieces.append(("p", body))
    chunks = []
    last = len(pieces) - 1
    for index, (kind, value) in enumerate(pieces):
        if kind == "h":
            chunks.append(mail_heading(value))
        else:
            chunks.append(mail_pre(value, gap=index != last))
    return "".join(chunks)

plain_advice = advice_plain(advice)
html_advice = advice_html(advice) if advice else ""
path = Path(os.environ["MAIL_TEMPLATE_FILE"])
try:
    tpl = path.read_text(encoding="utf-8")
except OSError as exc:
    unread = os.environ.get("TEXT_TEMPLATE_UNREADABLE") or "unreadable template: {1}"
    print(unread.replace("{1}", str(exc)), file=sys.stderr)
    sys.exit(1)
if not os.environ.get("MAIL_SUBTITLE", "").strip():
    os.environ["MAIL_SUBTITLE"] = " • ".join(
        part
        for part in (
            os.environ.get("PROJECT_NAME", ""),
            os.environ.get("HOSTNAME", ""),
            os.environ.get("DATE", ""),
        )
        if part
    )
if not os.environ.get("MAIL_FOOTER", "").strip():
    os.environ["MAIL_FOOTER"] = os.environ.get("PROJECT_NAME", "")
for name, content_key in (
    ("BLOCK_SERVICES", "MAIL_SERVICES"),
    ("BLOCK_FILES", "MAIL_FILES"),
    ("BLOCK_ACTIONS", "MAIL_ACTIONS"),
    ("BLOCK_IGNORE", "MAIL_IGNORE"),
):
    if not os.environ.get(content_key, "").strip():
        tpl = re.sub(
            r"<!--" + name + r"_START-->.*?<!--" + name + r"_END-->",
            "",
            tpl,
            count=1,
            flags=re.S,
        )
for key in ("TITLE", "PROJECT_NAME", "HOSTNAME", "DATE", "MODULE_NAME", "MAIL_LANG", "MAIL_MODULE", "MAIL_READ", "MAIL_SEEN", "MAIL_CHECK", "MAIL_NEXT", "MAIL_SUBTITLE", "MAIL_FOOTER", "MAIL_BLOCK_SERVICES", "MAIL_BLOCK_FILES", "MAIL_BLOCK_ACTIONS", "MAIL_BLOCK_IGNORE", "MAIL_SERVICES", "MAIL_FILES", "MAIL_ACTIONS", "MAIL_IGNORE"):
    tpl = tpl.replace("${" + key + "}", html.escape(os.environ.get(key, ""), quote=False))
tpl = tpl.replace("${CONTENT}", html.escape(content, quote=False))
if advice:
    tpl = tpl.replace("${ADVICE}", html.escape(plain_advice, quote=False))
    tpl = tpl.replace("${ADVICE_HTML}", html_advice)
else:
    tpl = re.sub(r"<!--ADVICE_START-->.*?<!--ADVICE_END-->", "", tpl, count=1, flags=re.S)
if note and note_cmd:
    tpl = tpl.replace("${NOTE}", html.escape(note, quote=False))
    tpl = tpl.replace("${NOTE_CMD}", html.escape(note_cmd, quote=False))
else:
    tpl = re.sub(r"<!--NOTE_START-->.*?<!--NOTE_END-->", "", tpl, count=1, flags=re.S)
if "<pre" not in tpl:
    missing_pre = os.environ.get("TEXT_TEMPLATE_NO_PRE") or "template without a pre tag"
    print(missing_pre, file=sys.stderr)
    sys.exit(1)
sys.stdout.write(tpl)
