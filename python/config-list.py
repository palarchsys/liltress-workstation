#!/usr/bin/env python3
# =============================================================================
# File       : python/config-list.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import csv
import io
import json
import os
import re
import sys
from pathlib import Path

root = Path(os.environ["CONFIG_SCHEMA_ROOT"])
mode = os.environ["CONFIG_SCHEMA_MODE"]
products = ("workstation", "server")
conf_names = ("global.conf", "user.conf", "secrets.conf")
assign_re = re.compile(r"^([A-Z][A-Z0-9_]*)=(.*)$")
public_keys = (
    "lot", "kind", "required", "empty_allowed", "choices", "pattern",
    "minimum", "maximum", "minimum_length", "maximum_length", "exclude",
    "forbidden", "reject", "separator", "mask_maximum", "port_minimum",
    "port_maximum", "equals", "distinct_from", "distinct_in", "when",
    "empty_when", "basic_fill", "computed", "resolves_to",
)
profiles = ["MATRIX", "LIVEKIT", "WIREGUARD"]
excluded_users = [
    "root", "daemon", "bin", "sys", "sync", "games", "man", "lp", "mail",
    "news", "uucp", "proxy", "www-data", "backup", "list", "irc", "nobody",
]
mail_names = (
    "POSTFIX_SMTP_LOGIN", "POSTFIX_MAIL_ADDRESS", "POSTFIX_MAIL_PASSWORD",
    "POSTFIX_MAIL_SMTP", "WATCHDOG_MAIL",
)
mail_when = {"name": "MAIL_ALERTS", "value": "1"}
mail_empty = {"name": "MAIL_ALERTS", "value": "0"}


def die(text):
    print(text, file=sys.stderr)
    raise SystemExit(1)


def choice(values, **extra):
    extra["kind"] = "choice"
    extra["choices"] = list(values)
    return extra


def integer(low, high, **extra):
    extra["kind"] = "integer"
    extra["minimum"] = low
    extra["maximum"] = high
    return extra


def shaped(kind, pattern, **extra):
    extra["kind"] = kind
    extra["pattern"] = pattern
    return extra


def flag():
    return choice(("0", "1"), required=True)


def mail_rule(kind, **extra):
    extra["kind"] = kind
    extra["when"] = mail_when
    extra["empty_when"] = mail_empty
    return extra


rules = {product: {} for product in products}
lots = {product: [] for product in products}


def put(product, name, lot, ask, spec):
    if name in rules[product]:
        die(f"duplicate rule {product} {name}")
    item = dict(spec)
    item["lot"] = lot
    item["ask"] = ask
    item.setdefault("required", False)
    rules[product][name] = item


def put_both(name, lot, ask, spec):
    for product in products:
        put(product, name, lot, ask, spec)


def add_lot(product, lot, names):
    lots[product].append((lot, list(names)))


email = shaped("email", r"^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$", required=True)
user_name = shaped(
    "user", r"^[a-z_][a-z0-9_-]{0,31}$", required=True, exclude=excluded_users,
)
hostname = shaped(
    "hostname", r"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", required=True,
)
absolute = shaped(
    "path", r"^/[A-Za-z0-9._/-]+$", required=True, reject=[".."],
)
project_name = shaped(
    "pattern", r"^[A-Za-z0-9][A-Za-z0-9 ._-]{0,62}$", required=True,
)
project_version = shaped(
    "pattern", r"^[0-9]+(\.[0-9]+){0,2}$", required=True,
)
languages = choice(("en", "fr", "de", "es"))
banner = {"kind": "text", "required": True, "forbidden": ["$(", "`"]}
template_name = shaped(
    "pattern", r"^[A-Za-z0-9][A-Za-z0-9._-]*\.html$", required=True,
)
pro_token = shaped("secret", r"^[A-Za-z0-9]{6,100}$", required=True)
secret_value = shaped(
    "secret", r"^[A-Za-z0-9@#%+=:./_-]{16,128}$", required=True,
)
turnstile = shaped("secret", r"^[A-Za-z0-9_-]{10,200}$", required=True)
smtp = shaped(
    "smtp",
    r"^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?:[0-9]+$",
    port_minimum=1,
    port_maximum=65535,
    reject=[".."],
)
watchdog_cpu = integer(1, 100, required=True)
watchdog_nice = integer(0, 19, required=True)
watchdog_io = integer(0, 7, required=True)

put_both("LANGUAGE", "language", True, languages)
put_both("MAIL_ALERTS", "alerts", True, flag())
put("workstation", "UBUNTU_PRO_TOKEN", "token", True, pro_token)
put("server", "UBUNTU_PRO_TOKEN", "token", True, shaped(
    "secret", r"^[A-Za-z0-9]{6,100}$", empty_allowed=True,
))
put_both("POSTFIX_SMTP_LOGIN", "mail", True, mail_rule("email", pattern=email["pattern"]))
put_both("POSTFIX_MAIL_ADDRESS", "mail", True, mail_rule("email", pattern=email["pattern"]))
put_both("POSTFIX_MAIL_PASSWORD", "mail", True, mail_rule("secret", **{
    "minimum_length": 8,
    "maximum_length": 128,
    "forbidden": [" ", '"', "'", "$", "\\", "`"],
}))
put_both("POSTFIX_MAIL_SMTP", "mail", True, mail_rule(
    "smtp",
    pattern=smtp["pattern"],
    port_minimum=1,
    port_maximum=65535,
    reject=[".."],
))
put_both("WATCHDOG_MAIL", "mail", True, mail_rule(
    "email", pattern=email["pattern"], equals="POSTFIX_MAIL_ADDRESS",
))
put_both("CONFIG_PREPARED", "prepared", False, choice(("1",), required=True))
put_both("SECRET_PREPARED", "prepared", False, choice(("1",), required=True))
put_both("BANNER_MESSAGE", "banner", True, banner)
put_both("SSH_BANNER_PATH", "banner", True, absolute)
put_both("MAIL_TEMPLATE", "template", True, template_name)
put_both("WATCHDOG_CPU_LIMIT", "watchdog", True, watchdog_cpu)
put_both("WATCHDOG_LIMIT_NICE", "watchdog", True, watchdog_nice)
put_both("WATCHDOG_LIMIT_IO_NICE", "watchdog", True, watchdog_io)
put("workstation", "PROJECT_VERSION", "identity", True, project_version)
put("server", "PROJECT_VERSION", "version", True, project_version)

put("workstation", "PROJECT_NAME", "identity", True, project_name)
put("workstation", "PROJECT_SLUG", "identity", True, choice(
    ("liltress-workstation",), required=True,
))
put("workstation", "CONFIG_BASE_DIRECTORY", "paths", True, choice(
    ("/opt/liltress-workstation",), required=True,
))
put("workstation", "SECRET_DIRECTORY", "paths", False, {
    "kind": "template", "computed": True, "resolves_to": "/opt/liltress-workstation/secrets",
})
put("workstation", "LYNIS_MIN_SCORE", "audit", True, integer(0, 100, required=True))
put("workstation", "SSH_SERVICE_NAME", "ssh", True, choice(("ssh",), required=True))
put("workstation", "SSH_MAX_AUTH_TRIES", "ssh", True, integer(1, 10, required=True))
put("workstation", "SSH_CLIENT_ALIVE_INTERVAL", "ssh", True, integer(30, 3600, required=True))
put("workstation", "SSH_CLIENT_ALIVE_COUNT_MAX", "ssh", True, integer(1, 10, required=True))
put("workstation", "SSH_LOGIN_GRACE_TIME", "ssh", True, integer(10, 120, required=True))
put("workstation", "PAM_PASSWORD_MIN_LENGTH", "pam", True, integer(8, 32, required=True))
put("workstation", "FAILLOCK_DENY", "pam", True, integer(3, 20, required=True))
put("workstation", "FAILLOCK_UNLOCK", "pam", True, integer(60, 86400, required=True))
put("workstation", "FAILLOCK_FAIL_INTERVAL", "pam", True, integer(60, 86400, required=True))

put("server", "PROJECT_NAME", "site", True, project_name)
put("server", "DOMAIN", "site", True, shaped(
    "domain",
    r"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$",
    required=True,
))
put("server", "MAIN_USER", "account", True, {**user_name, "distinct_from": ["CRON_USER"]})
put("server", "MAIN_GROUP", "account", True, user_name)
put("server", "SSH_PORT", "account", True, integer(
    1024, 65535, required=True, distinct_in=list(profiles),
))
put("server", "MODE_TEST", "mode", True, flag())
put("server", "MODE_DEV", "mode", True, flag())
put("server", "LYNIS_MIN_SCORE", "audit", True, integer(0, 100, required=True))
put("server", "NGINX_CERTBOT_MAIL_ADDRESS", "certificate", True, email)
put("server", "ANTIBOT_HMAC_SECRET", "web-secret", True, {**secret_value, "basic_fill": "hex-32"})
put("server", "POSTGRES_WEB_PASSWORD", "web-secret", True, {**secret_value, "basic_fill": "hex-32"})
put("server", "TURNSTILE_SITE_KEY", "web-secret", True, {**turnstile, "basic_fill": "turnstile-site"})
put("server", "TURNSTILE_SECRET_KEY", "web-secret", True, {**turnstile, "basic_fill": "turnstile-secret"})
put("server", "CONFIG_BASE_DIRECTORY", "paths", True, choice(("/opt/liltress",), required=True))
put("server", "SECRET_DIRECTORY", "paths", False, {
    "kind": "template", "computed": True, "resolves_to": "/opt/liltress/secrets",
})
put("server", "DOCKER_BASE_DIRECTORY", "paths", False, {
    "kind": "template", "computed": True, "resolves_to": "/opt/liltress/docker",
})
put("server", "SSH_SERVICE_NAME", "ssh", True, shaped(
    "pattern", r"^[a-z][a-z0-9-]*$", required=True,
))
put("server", "SSH_MAX_AUTH_TRIES", "ssh", True, integer(1, 10, required=True))
put("server", "SSH_CLIENT_ALIVE_INTERVAL", "ssh", True, integer(0, 3600, required=True))
put("server", "SSH_CLIENT_ALIVE_COUNT_MAX", "ssh", True, integer(0, 10, required=True))
put("server", "UNBOUND_FORWARDERS", "resolver", True, {
    "kind": "ipv4-list",
    "separator": " ",
    "pattern": r"^([0-9]{1,3}\.){3}[0-9]{1,3}$",
    "required": True,
})
put("server", "USBGUARD_ENABLE", "resolver", True, flag())
put("server", "DDOS_HARDENING_LEVEL", "resolver", True, choice(("1", "2", "3"), required=True))
for host_name in ("HOSTNAME_MATRIX", "HOSTNAME_LIVEKIT", "HOSTNAME_WIREGUARD"):
    put("server", host_name, "hosts", True, hostname)
put("server", "SWAP_SIZE", "swap", True, shaped(
    "pattern", r"^[1-9][0-9]*[KMGT]$", required=True,
))
put("server", "SWAP_FILE", "swap", True, absolute)
put("server", "SWAP_MAPPER_NAME", "swap", True, shaped(
    "pattern", r"^[a-z][a-z0-9_-]{0,31}$", required=True,
))
put("server", "CRON_USER", "cron", True, {**user_name, "distinct_from": ["MAIN_USER"]})
put("server", "NGINX_ADMIN_USER", "nginx", True, user_name)
put("server", "NGINX_HTPASSWD_PATH", "nginx", True, shaped(
    "path", r"^/[A-Za-z0-9._/-]+$", required=True,
))
put("server", "NGINX_HTPASSWD_REALM", "nginx", True, {
    "kind": "text", "required": True, "forbidden": ['"', "$"],
})
put("server", "DOCKER_NETWORK_PRODUCTION", "docker-network", True, shaped(
    "cidr", r"^([0-9.]+)/([0-9]+)$", required=True, mask_maximum=32,
    distinct_from=["DOCKER_NETWORK_SECURITY"],
))
put("server", "DOCKER_NETWORK_SECURITY", "docker-network", True, shaped(
    "cidr", r"^([0-9.]+)/([0-9]+)$", required=True, mask_maximum=32,
    distinct_from=["DOCKER_NETWORK_PRODUCTION"],
))
put("server", "DOCKER_LOG_DRIVER", "docker-log", True, choice(
    ("local", "json-file", "journald"), required=True,
))
put("server", "DOCKER_LOG_MAX_SIZE", "docker-log", True, shaped(
    "pattern", r"^[1-9][0-9]*[kmgKMG]?$", required=True,
))
put("server", "DOCKER_LOG_MAX_FILE", "docker-log", True, integer(1, 20, required=True))
put("server", "DOCKER_LOG_COMPRESS", "docker-log", True, choice(("true", "false"), required=True))
for database_name in (
    "POSTGRES_SYNAPSE_USER", "POSTGRES_SYNAPSE_DB", "POSTGRES_KEYCLOAK_USER",
    "POSTGRES_KEYCLOAK_DB", "POSTGRES_WEB_USER", "POSTGRES_WEB_DB",
):
    put("server", database_name, "postgres", True, shaped(
        "pattern", r"^[a-z][a-z0-9_]{0,30}$", required=True,
    ))
server_ports = {
    "PORT_CROWDSEC_LAPI": profiles,
    "PORT_SYNAPSE_POSTGRESQL": ["MATRIX"],
    "PORT_SYNAPSE": ["MATRIX"],
    "PORT_ELEMENT": ["MATRIX"],
    "PORT_WEB_UI": ["MATRIX"],
    "PORT_WEB_API": ["MATRIX"],
    "PORT_SYNAPSE_ADMIN": ["MATRIX"],
    "PORT_PROMETHEUS": ["MATRIX"],
    "PORT_KEYCLOAK": ["MATRIX"],
    "PORT_LIVEKIT_SFU": ["LIVEKIT"],
    "PORT_LIVEKIT_JWT": ["LIVEKIT"],
    "PORT_LIVEKIT_REDIS": ["LIVEKIT"],
    "PORT_WIREGUARD_UI": ["WIREGUARD"],
    "PORT_WIREGUARD_UDP": ["WIREGUARD"],
}
for port_name, port_profiles in server_ports.items():
    put("server", port_name, "ports", True, integer(
        1, 65535, required=True, distinct_in=list(port_profiles),
    ))
put("server", "WEB_REGISTRY", "web", True, shaped(
    "pattern",
    r"^[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]+)?(/[a-z0-9._-]+)+$",
    required=True,
))
put("server", "WEB_IMAGE_FRONTEND", "web", True, shaped(
    "pattern", r"^[a-z0-9][a-z0-9._-]{0,80}$", required=True,
))
put("server", "WEB_IMAGE_BACKEND", "web", True, shaped(
    "pattern", r"^[a-z0-9][a-z0-9._-]{0,80}$", required=True,
))
put("server", "WEB_IMAGE_TAG", "web", True, shaped(
    "pattern", r"^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", required=True,
))
put("server", "WEB_UPDATE_SCRIPT", "web", True, shaped(
    "path", r"^/usr/local/bin/[A-Za-z0-9._-]+$", required=True,
))
put("server", "MATRIX_ADMIN_USER", "matrix", True, shaped(
    "pattern", r"^[a-z][a-z0-9_-]{2,31}$", required=True,
))
put("server", "KEYCLOAK_REALM", "keycloak", True, shaped(
    "pattern", r"^[a-z][a-z0-9-]{1,62}$", required=True,
))
put("server", "KEYCLOAK_CLIENT", "keycloak", True, shaped(
    "pattern", r"^[a-z][a-z0-9-]{1,62}$", required=True,
))
put("server", "KC_BOOTSTRAP_ADMIN_USERNAME", "keycloak", True, shaped(
    "pattern", r"^[a-z][a-z0-9_-]{2,31}$", required=True,
))
put("server", "WIREGUARD_DEFAULT_DNS", "wireguard", True, shaped(
    "pattern", r"^[0-9.]+(,[0-9.]+)*$", required=True,
))
put("server", "WIREGUARD_DEFAULT_ADDRESS", "wireguard", True, shaped(
    "pattern", r"^([0-9]{1,3}\.){3}x$", required=True,
))
put("server", "WIREGUARD_ALLOWED_IP", "wireguard", True, shaped(
    "pattern", r"^[0-9a-fA-F.:/,]+$", required=True,
))

derived_paths = {
    "DOCKER_DIRECTORY_MATRIX": "/opt/liltress/docker/matrix",
    "DOCKER_DIRECTORY_LIVEKIT": "/opt/liltress/docker/livekit",
    "DOCKER_DIRECTORY_WIREGUARD": "/opt/liltress/docker/wireguard",
    "DOCKER_DIRECTORY_SECURITY": "/opt/liltress/docker/security",
    "ENV_FILE_MATRIX": "/opt/liltress/secrets/matrix.env",
    "ENV_FILE_LIVEKIT": "/opt/liltress/secrets/livekit.env",
    "ENV_FILE_WIREGUARD": "/opt/liltress/secrets/wireguard.env",
    "ENV_FILE_SECURITY": "/opt/liltress/secrets/security.env",
    "ENV_FILE_WEB": "/opt/liltress/secrets/web.env",
}
for derived_name, resolved in derived_paths.items():
    lot_name = "paths"
    put("server", derived_name, lot_name, False, {
        "kind": "template", "computed": True, "resolves_to": resolved,
    })
for derived_name in (
    "DOMAIN_SYNAPSE", "DOMAIN_ELEMENT", "DOMAIN_SYNAPSE_ADMIN", "DOMAIN_PROMETHEUS",
    "DOMAIN_KEYCLOAK", "DOMAIN_LIVEKIT_JWT", "DOMAIN_LIVEKIT_SFU", "DOMAIN_WIREGUARD",
    "DOMAIN_WEB_API", "MATRIX_SERVER_NAME", "MATRIX_PUBLIC_BASE_URL",
    "ELEMENT_PUBLIC_BASE_URL", "KEYCLOAK_PUBLIC_BASE_URL",
):
    put("server", derived_name, "domain", False, {"kind": "template", "computed": True})

add_lot("workstation", "language", ["LANGUAGE"])
add_lot("workstation", "token", ["UBUNTU_PRO_TOKEN"])
add_lot("workstation", "alerts", ["MAIL_ALERTS"])
add_lot("workstation", "mail", mail_names)
add_lot("workstation", "identity", ["PROJECT_NAME", "PROJECT_SLUG", "PROJECT_VERSION"])
add_lot("workstation", "paths", ["CONFIG_BASE_DIRECTORY"])
add_lot("workstation", "audit", ["LYNIS_MIN_SCORE"])
add_lot("workstation", "banner", ["BANNER_MESSAGE", "SSH_BANNER_PATH"])
add_lot("workstation", "ssh", [
    "SSH_SERVICE_NAME", "SSH_MAX_AUTH_TRIES", "SSH_CLIENT_ALIVE_INTERVAL",
    "SSH_CLIENT_ALIVE_COUNT_MAX", "SSH_LOGIN_GRACE_TIME",
])
add_lot("workstation", "watchdog", [
    "WATCHDOG_CPU_LIMIT", "WATCHDOG_LIMIT_NICE", "WATCHDOG_LIMIT_IO_NICE",
])
add_lot("workstation", "template", ["MAIL_TEMPLATE"])
add_lot("workstation", "pam", [
    "PAM_PASSWORD_MIN_LENGTH", "FAILLOCK_DENY", "FAILLOCK_UNLOCK", "FAILLOCK_FAIL_INTERVAL",
])

add_lot("server", "language", ["LANGUAGE"])
add_lot("server", "site", ["PROJECT_NAME", "DOMAIN"])
add_lot("server", "account", ["MAIN_USER", "MAIN_GROUP", "SSH_PORT"])
add_lot("server", "token", ["UBUNTU_PRO_TOKEN"])
add_lot("server", "mode", ["MODE_TEST", "MODE_DEV"])
add_lot("server", "audit", ["LYNIS_MIN_SCORE"])
add_lot("server", "alerts", ["MAIL_ALERTS"])
add_lot("server", "mail", mail_names)
add_lot("server", "certificate", ["NGINX_CERTBOT_MAIL_ADDRESS"])
add_lot("server", "web-secret", [
    "ANTIBOT_HMAC_SECRET", "POSTGRES_WEB_PASSWORD",
    "TURNSTILE_SITE_KEY", "TURNSTILE_SECRET_KEY",
])
add_lot("server", "version", ["PROJECT_VERSION"])
add_lot("server", "paths", ["CONFIG_BASE_DIRECTORY"])
add_lot("server", "banner", ["BANNER_MESSAGE", "SSH_BANNER_PATH"])
add_lot("server", "ssh", [
    "SSH_SERVICE_NAME", "SSH_MAX_AUTH_TRIES", "SSH_CLIENT_ALIVE_INTERVAL",
    "SSH_CLIENT_ALIVE_COUNT_MAX",
])
add_lot("server", "watchdog", [
    "WATCHDOG_CPU_LIMIT", "WATCHDOG_LIMIT_NICE", "WATCHDOG_LIMIT_IO_NICE",
])
add_lot("server", "template", ["MAIL_TEMPLATE"])
add_lot("server", "resolver", ["UNBOUND_FORWARDERS", "USBGUARD_ENABLE", "DDOS_HARDENING_LEVEL"])
add_lot("server", "hosts", ["HOSTNAME_MATRIX", "HOSTNAME_LIVEKIT", "HOSTNAME_WIREGUARD"])
add_lot("server", "swap", ["SWAP_SIZE", "SWAP_FILE", "SWAP_MAPPER_NAME"])
add_lot("server", "cron", ["CRON_USER"])
add_lot("server", "nginx", ["NGINX_ADMIN_USER", "NGINX_HTPASSWD_PATH", "NGINX_HTPASSWD_REALM"])
add_lot("server", "docker-network", ["DOCKER_NETWORK_PRODUCTION", "DOCKER_NETWORK_SECURITY"])
add_lot("server", "docker-log", [
    "DOCKER_LOG_DRIVER", "DOCKER_LOG_MAX_SIZE", "DOCKER_LOG_MAX_FILE", "DOCKER_LOG_COMPRESS",
])
add_lot("server", "postgres", [
    "POSTGRES_SYNAPSE_USER", "POSTGRES_SYNAPSE_DB", "POSTGRES_KEYCLOAK_USER",
    "POSTGRES_KEYCLOAK_DB", "POSTGRES_WEB_USER", "POSTGRES_WEB_DB",
])
add_lot("server", "ports", list(server_ports))
add_lot("server", "web", [
    "WEB_REGISTRY", "WEB_IMAGE_FRONTEND", "WEB_IMAGE_BACKEND",
    "WEB_IMAGE_TAG", "WEB_UPDATE_SCRIPT",
])
add_lot("server", "matrix", ["MATRIX_ADMIN_USER"])
add_lot("server", "keycloak", ["KEYCLOAK_REALM", "KEYCLOAK_CLIENT", "KC_BOOTSTRAP_ADMIN_USERNAME"])
add_lot("server", "wireguard", [
    "WIREGUARD_DEFAULT_DNS", "WIREGUARD_DEFAULT_ADDRESS", "WIREGUARD_ALLOWED_IP",
])

asked = {}
for product, groups in lots.items():
    names = []
    for _lot, grouped in groups:
        names.extend(grouped)
    if len(names) != len(set(names)):
        die(f"duplicate list name in {product}")
    asked[product] = names
    for name in names:
        if name not in rules[product] or not rules[product][name]["ask"]:
            die(f"list name is not a parameter {product} {name}")
    for name, rule in rules[product].items():
        if rule["ask"] and name not in names:
            die(f"parameter missing from lists {product} {name}")


def parse_conf(path, filename):
    lines = path.read_text(encoding="utf-8").splitlines()
    found = []
    index = 0
    while index < len(lines):
        match = assign_re.match(lines[index])
        if not match:
            index += 1
            continue
        name, raw = match.group(1), match.group(2)
        if raw.startswith('"') and not raw.endswith('"'):
            parts = [raw]
            index += 1
            while index < len(lines):
                parts.append(lines[index])
                if lines[index].endswith('"'):
                    break
                index += 1
            else:
                die(f"unclosed value in {filename} {name}")
            raw = "\n".join(parts)
        computed = "${" in raw
        value = None
        if filename != "secrets.conf":
            if len(raw) >= 2 and raw.startswith('"') and raw.endswith('"'):
                value = raw[1:-1]
            else:
                value = raw
        found.append({
            "name": name,
            "file": filename,
            "computed": computed,
            "value": value,
        })
        index += 1
    return found


def publish(product, item):
    rule = rules[product][item["name"]]
    if bool(rule.get("computed")) != item["computed"]:
        die(f"computed flag differs {product} {item['name']}")
    body = {"name": item["name"], "file": item["file"]}
    for key in public_keys:
        if key in rule:
            body[key] = rule[key]
    if item["file"] == "secrets.conf":
        if "default" in body:
            die(f"secret default refused {item['name']}")
        return body
    value = item["value"]
    if rule["kind"] == "integer":
        if not re.fullmatch(r"[0-9]+", value or ""):
            die(f"integer default refused {product} {item['name']}")
        number = int(value)
        if number < rule["minimum"] or number > rule["maximum"]:
            die(f"integer default outside range {product} {item['name']}")
        body["default"] = number
    elif rule["kind"] == "choice":
        text = "" if value is None else str(value)
        if text not in rule["choices"]:
            die(f"choice default refused {product} {item['name']}")
        body["default"] = text
    else:
        body["default"] = value
    return body


def file_record(filename):
    record = {"name": filename, "syntax": "shell", "sources": []}
    if filename == "global.conf":
        record["mode"] = "644"
        record["sources"] = [
            "${INSTALL_DIRECTORY}/config/user.conf",
            "${INSTALL_DIRECTORY}/config/secrets.conf",
        ]
    elif filename == "user.conf":
        record["mode"] = "644"
    else:
        record["mode"] = "600"
    return record


allowed = {
    "workstation": ["INSTALL_DIRECTORY", "PROJECT_SLUG", "CONFIG_BASE_DIRECTORY"],
    "server": [
        "DOMAIN", "CONFIG_BASE_DIRECTORY", "DOCKER_BASE_DIRECTORY", "SECRET_DIRECTORY",
        "DOMAIN_SYNAPSE", "DOMAIN_ELEMENT", "DOMAIN_KEYCLOAK", "MAIN_GROUP",
        "INSTALL_DIRECTORY",
    ],
}

# One clear label per listed variable, in every language. The key is LABEL_<NAME>.
labels = {
    "LANGUAGE": {"en": "Language", "fr": "Langue", "de": "Sprache", "es": "Idioma"},
    "UBUNTU_PRO_TOKEN": {"en": "Ubuntu Pro token", "fr": "Jeton Ubuntu Pro", "de": "Ubuntu-Pro-Token", "es": "Token de Ubuntu Pro"},
    "MAIL_ALERTS": {"en": "Email alerts", "fr": "Alertes e-mail", "de": "E-Mail-Alarme", "es": "Alertas por correo"},
    "POSTFIX_SMTP_LOGIN": {"en": "SMTP login", "fr": "Identifiant SMTP", "de": "SMTP-Anmeldung", "es": "Usuario SMTP"},
    "POSTFIX_MAIL_ADDRESS": {"en": "Sender email address", "fr": "Adresse e-mail de l'expéditeur", "de": "Absender-E-Mail-Adresse", "es": "Correo del remitente"},
    "POSTFIX_MAIL_PASSWORD": {"en": "SMTP password", "fr": "Mot de passe SMTP", "de": "SMTP-Passwort", "es": "Contraseña SMTP"},
    "POSTFIX_MAIL_SMTP": {"en": "SMTP server", "fr": "Serveur SMTP", "de": "SMTP-Server", "es": "Servidor SMTP"},
    "WATCHDOG_MAIL": {"en": "Alert recipient", "fr": "Destinataire des alertes", "de": "Empfänger der Alarme", "es": "Destinatario de las alertas"},
    "PROJECT_NAME": {"en": "Project name", "fr": "Nom du projet", "de": "Projektname", "es": "Nombre del proyecto"},
    "PROJECT_SLUG": {"en": "Project identifier", "fr": "Identifiant du projet", "de": "Projektkennung", "es": "Identificador del proyecto"},
    "PROJECT_VERSION": {"en": "Project version", "fr": "Version du projet", "de": "Projektversion", "es": "Versión del proyecto"},
    "CONFIG_BASE_DIRECTORY": {"en": "Install directory", "fr": "Répertoire d'installation", "de": "Installationsverzeichnis", "es": "Directorio de instalación"},
    "LYNIS_MIN_SCORE": {"en": "Minimum Lynis score", "fr": "Score Lynis minimal", "de": "Minimaler Lynis-Wert", "es": "Puntuación mínima de Lynis"},
    "BANNER_MESSAGE": {"en": "Login banner", "fr": "Bannière de connexion", "de": "Anmeldebanner", "es": "Banner de inicio de sesión"},
    "SSH_BANNER_PATH": {"en": "SSH banner file", "fr": "Fichier de la bannière SSH", "de": "SSH-Bannerdatei", "es": "Archivo del banner SSH"},
    "SSH_SERVICE_NAME": {"en": "SSH service name", "fr": "Nom du service SSH", "de": "Name des SSH-Dienstes", "es": "Nombre del servicio SSH"},
    "SSH_MAX_AUTH_TRIES": {"en": "Maximum SSH authentication tries", "fr": "Essais d'authentification SSH", "de": "Maximale SSH-Anmeldeversuche", "es": "Intentos máximos de autenticación SSH"},
    "SSH_CLIENT_ALIVE_INTERVAL": {"en": "SSH keepalive interval", "fr": "Intervalle de maintien SSH", "de": "SSH-Keepalive-Intervall", "es": "Intervalo de keepalive SSH"},
    "SSH_CLIENT_ALIVE_COUNT_MAX": {"en": "SSH keepalive count", "fr": "Nombre de maintiens SSH", "de": "SSH-Keepalive-Anzahl", "es": "Número de keepalives SSH"},
    "SSH_LOGIN_GRACE_TIME": {"en": "SSH login grace time", "fr": "Délai de connexion SSH", "de": "SSH-Anmeldefrist", "es": "Tiempo de gracia de conexión SSH"},
    "WATCHDOG_CPU_LIMIT": {"en": "Watchdog CPU limit", "fr": "Limite CPU du contrôle", "de": "CPU-Limit der Überwachung", "es": "Límite de CPU del control"},
    "WATCHDOG_LIMIT_NICE": {"en": "Watchdog CPU priority", "fr": "Priorité CPU du contrôle", "de": "CPU-Priorität der Überwachung", "es": "Prioridad de CPU del control"},
    "WATCHDOG_LIMIT_IO_NICE": {"en": "Watchdog disk priority", "fr": "Priorité disque du contrôle", "de": "Festplattenpriorität der Überwachung", "es": "Prioridad de disco del control"},
    "MAIL_TEMPLATE": {"en": "Mail template", "fr": "Modèle de courrier", "de": "E-Mail-Vorlage", "es": "Plantilla de correo"},
    "PAM_PASSWORD_MIN_LENGTH": {"en": "Minimum password length", "fr": "Longueur minimale du mot de passe", "de": "Minimale Passwortlänge", "es": "Longitud mínima de la contraseña"},
    "FAILLOCK_DENY": {"en": "Failed attempts before lock", "fr": "Essais avant verrouillage", "de": "Versuche vor der Sperre", "es": "Intentos antes del bloqueo"},
    "FAILLOCK_UNLOCK": {"en": "Lock duration", "fr": "Durée du verrouillage", "de": "Sperrdauer", "es": "Duración del bloqueo"},
    "FAILLOCK_FAIL_INTERVAL": {"en": "Failed-attempt window", "fr": "Fenêtre des essais échoués", "de": "Zeitfenster der Fehlversuche", "es": "Ventana de intentos fallidos"},
    "DOMAIN": {"en": "Domain name", "fr": "Nom de domaine", "de": "Domainname", "es": "Nombre de dominio"},
    "MAIN_USER": {"en": "Main account", "fr": "Compte principal", "de": "Hauptkonto", "es": "Cuenta principal"},
    "MAIN_GROUP": {"en": "Main group", "fr": "Groupe principal", "de": "Hauptgruppe", "es": "Grupo principal"},
    "SSH_PORT": {"en": "SSH port", "fr": "Port SSH", "de": "SSH-Port", "es": "Puerto SSH"},
    "MODE_TEST": {"en": "Test mode", "fr": "Mode test", "de": "Testmodus", "es": "Modo de prueba"},
    "MODE_DEV": {"en": "Development mode", "fr": "Mode développement", "de": "Entwicklungsmodus", "es": "Modo de desarrollo"},
    "NGINX_CERTBOT_MAIL_ADDRESS": {"en": "Certificate email address", "fr": "Adresse e-mail du certificat", "de": "E-Mail-Adresse des Zertifikats", "es": "Correo del certificado"},
    "ANTIBOT_HMAC_SECRET": {"en": "Antibot secret", "fr": "Secret antibot", "de": "Antibot-Geheimnis", "es": "Secreto antibot"},
    "POSTGRES_WEB_PASSWORD": {"en": "Web database password", "fr": "Mot de passe de la base web", "de": "Passwort der Web-Datenbank", "es": "Contraseña de la base web"},
    "TURNSTILE_SITE_KEY": {"en": "Turnstile site key", "fr": "Clé de site Turnstile", "de": "Turnstile-Site-Schlüssel", "es": "Clave de sitio Turnstile"},
    "TURNSTILE_SECRET_KEY": {"en": "Turnstile secret key", "fr": "Clé secrète Turnstile", "de": "Turnstile-Geheimschlüssel", "es": "Clave secreta Turnstile"},
    "UNBOUND_FORWARDERS": {"en": "DNS forwarders", "fr": "Relais DNS", "de": "DNS-Weiterleitungen", "es": "Reenviadores DNS"},
    "USBGUARD_ENABLE": {"en": "Enable USBGuard", "fr": "Activer USBGuard", "de": "USBGuard aktivieren", "es": "Activar USBGuard"},
    "DDOS_HARDENING_LEVEL": {"en": "DDoS hardening level", "fr": "Niveau de durcissement DDoS", "de": "DDoS-Härtungsstufe", "es": "Nivel de endurecimiento DDoS"},
    "HOSTNAME_MATRIX": {"en": "Matrix hostname", "fr": "Nom d'hôte Matrix", "de": "Matrix-Hostname", "es": "Nombre de host Matrix"},
    "HOSTNAME_LIVEKIT": {"en": "LiveKit hostname", "fr": "Nom d'hôte LiveKit", "de": "LiveKit-Hostname", "es": "Nombre de host LiveKit"},
    "HOSTNAME_WIREGUARD": {"en": "WireGuard hostname", "fr": "Nom d'hôte WireGuard", "de": "WireGuard-Hostname", "es": "Nombre de host WireGuard"},
    "SWAP_SIZE": {"en": "Swap size", "fr": "Taille du swap", "de": "Swap-Größe", "es": "Tamaño del swap"},
    "SWAP_FILE": {"en": "Swap file", "fr": "Fichier de swap", "de": "Swap-Datei", "es": "Archivo de swap"},
    "SWAP_MAPPER_NAME": {"en": "Swap mapper name", "fr": "Nom du mappeur de swap", "de": "Name des Swap-Mappers", "es": "Nombre del mapeador de swap"},
    "CRON_USER": {"en": "Cron account", "fr": "Compte cron", "de": "Cron-Konto", "es": "Cuenta cron"},
    "NGINX_ADMIN_USER": {"en": "Nginx admin account", "fr": "Compte admin Nginx", "de": "Nginx-Adminkonto", "es": "Cuenta de admin Nginx"},
    "NGINX_HTPASSWD_PATH": {"en": "Nginx password file", "fr": "Fichier de mots de passe Nginx", "de": "Nginx-Passwortdatei", "es": "Archivo de contraseñas Nginx"},
    "NGINX_HTPASSWD_REALM": {"en": "Nginx authentication realm", "fr": "Domaine d'authentification Nginx", "de": "Nginx-Authentifizierungsbereich", "es": "Reino de autenticación Nginx"},
    "DOCKER_NETWORK_PRODUCTION": {"en": "Production Docker network", "fr": "Réseau Docker de production", "de": "Docker-Netz der Produktion", "es": "Red Docker de producción"},
    "DOCKER_NETWORK_SECURITY": {"en": "Security Docker network", "fr": "Réseau Docker de sécurité", "de": "Docker-Netz der Sicherheit", "es": "Red Docker de seguridad"},
    "DOCKER_LOG_DRIVER": {"en": "Docker log driver", "fr": "Pilote de journaux Docker", "de": "Docker-Protokolltreiber", "es": "Controlador de registros Docker"},
    "DOCKER_LOG_MAX_SIZE": {"en": "Docker log file size", "fr": "Taille d'un journal Docker", "de": "Größe einer Docker-Protokolldatei", "es": "Tamaño de un registro Docker"},
    "DOCKER_LOG_MAX_FILE": {"en": "Docker log file count", "fr": "Nombre de journaux Docker", "de": "Anzahl der Docker-Protokolldateien", "es": "Número de registros Docker"},
    "DOCKER_LOG_COMPRESS": {"en": "Compress Docker logs", "fr": "Compresser les journaux Docker", "de": "Docker-Protokolle komprimieren", "es": "Comprimir los registros Docker"},
    "POSTGRES_SYNAPSE_USER": {"en": "Synapse database account", "fr": "Compte de la base Synapse", "de": "Konto der Synapse-Datenbank", "es": "Cuenta de la base Synapse"},
    "POSTGRES_SYNAPSE_DB": {"en": "Synapse database name", "fr": "Nom de la base Synapse", "de": "Name der Synapse-Datenbank", "es": "Nombre de la base Synapse"},
    "POSTGRES_KEYCLOAK_USER": {"en": "Keycloak database account", "fr": "Compte de la base Keycloak", "de": "Konto der Keycloak-Datenbank", "es": "Cuenta de la base Keycloak"},
    "POSTGRES_KEYCLOAK_DB": {"en": "Keycloak database name", "fr": "Nom de la base Keycloak", "de": "Name der Keycloak-Datenbank", "es": "Nombre de la base Keycloak"},
    "POSTGRES_WEB_USER": {"en": "Web database account", "fr": "Compte de la base web", "de": "Konto der Web-Datenbank", "es": "Cuenta de la base web"},
    "POSTGRES_WEB_DB": {"en": "Web database name", "fr": "Nom de la base web", "de": "Name der Web-Datenbank", "es": "Nombre de la base web"},
    "PORT_CROWDSEC_LAPI": {"en": "CrowdSec LAPI port", "fr": "Port LAPI CrowdSec", "de": "CrowdSec-LAPI-Port", "es": "Puerto LAPI de CrowdSec"},
    "PORT_SYNAPSE_POSTGRESQL": {"en": "Synapse PostgreSQL port", "fr": "Port PostgreSQL de Synapse", "de": "Synapse-PostgreSQL-Port", "es": "Puerto PostgreSQL de Synapse"},
    "PORT_SYNAPSE": {"en": "Synapse port", "fr": "Port Synapse", "de": "Synapse-Port", "es": "Puerto Synapse"},
    "PORT_ELEMENT": {"en": "Element port", "fr": "Port Element", "de": "Element-Port", "es": "Puerto Element"},
    "PORT_WEB_UI": {"en": "Web interface port", "fr": "Port de l'interface web", "de": "Port der Weboberfläche", "es": "Puerto de la interfaz web"},
    "PORT_WEB_API": {"en": "Web API port", "fr": "Port de l'API web", "de": "Port der Web-API", "es": "Puerto de la API web"},
    "PORT_SYNAPSE_ADMIN": {"en": "Synapse admin port", "fr": "Port d'admin Synapse", "de": "Synapse-Admin-Port", "es": "Puerto de admin Synapse"},
    "PORT_PROMETHEUS": {"en": "Prometheus port", "fr": "Port Prometheus", "de": "Prometheus-Port", "es": "Puerto Prometheus"},
    "PORT_KEYCLOAK": {"en": "Keycloak port", "fr": "Port Keycloak", "de": "Keycloak-Port", "es": "Puerto Keycloak"},
    "PORT_LIVEKIT_SFU": {"en": "LiveKit SFU port", "fr": "Port SFU LiveKit", "de": "LiveKit-SFU-Port", "es": "Puerto SFU de LiveKit"},
    "PORT_LIVEKIT_JWT": {"en": "LiveKit JWT port", "fr": "Port JWT LiveKit", "de": "LiveKit-JWT-Port", "es": "Puerto JWT de LiveKit"},
    "PORT_LIVEKIT_REDIS": {"en": "LiveKit Redis port", "fr": "Port Redis LiveKit", "de": "LiveKit-Redis-Port", "es": "Puerto Redis de LiveKit"},
    "PORT_WIREGUARD_UI": {"en": "WireGuard interface port", "fr": "Port de l'interface WireGuard", "de": "WireGuard-Oberflächenport", "es": "Puerto de la interfaz WireGuard"},
    "PORT_WIREGUARD_UDP": {"en": "WireGuard UDP port", "fr": "Port UDP WireGuard", "de": "WireGuard-UDP-Port", "es": "Puerto UDP de WireGuard"},
    "WEB_REGISTRY": {"en": "Container registry", "fr": "Registre d'images", "de": "Container-Registry", "es": "Registro de imágenes"},
    "WEB_IMAGE_FRONTEND": {"en": "Frontend image", "fr": "Image du frontend", "de": "Frontend-Image", "es": "Imagen del frontend"},
    "WEB_IMAGE_BACKEND": {"en": "Backend image", "fr": "Image du backend", "de": "Backend-Image", "es": "Imagen del backend"},
    "WEB_IMAGE_TAG": {"en": "Image tag", "fr": "Étiquette d'image", "de": "Image-Tag", "es": "Etiqueta de imagen"},
    "WEB_UPDATE_SCRIPT": {"en": "Update script", "fr": "Script de mise à jour", "de": "Aktualisierungsskript", "es": "Script de actualización"},
    "MATRIX_ADMIN_USER": {"en": "Matrix admin account", "fr": "Compte admin Matrix", "de": "Matrix-Adminkonto", "es": "Cuenta de admin Matrix"},
    "KEYCLOAK_REALM": {"en": "Keycloak realm", "fr": "Royaume Keycloak", "de": "Keycloak-Realm", "es": "Reino Keycloak"},
    "KEYCLOAK_CLIENT": {"en": "Keycloak client", "fr": "Client Keycloak", "de": "Keycloak-Client", "es": "Cliente Keycloak"},
    "KC_BOOTSTRAP_ADMIN_USERNAME": {"en": "Keycloak bootstrap admin", "fr": "Admin initial Keycloak", "de": "Keycloak-Startadmin", "es": "Admin inicial de Keycloak"},
    "WIREGUARD_DEFAULT_DNS": {"en": "WireGuard DNS", "fr": "DNS WireGuard", "de": "WireGuard-DNS", "es": "DNS de WireGuard"},
    "WIREGUARD_DEFAULT_ADDRESS": {"en": "WireGuard address", "fr": "Adresse WireGuard", "de": "WireGuard-Adresse", "es": "Dirección WireGuard"},
    "WIREGUARD_ALLOWED_IP": {"en": "WireGuard allowed addresses", "fr": "Adresses autorisées WireGuard", "de": "Erlaubte WireGuard-Adressen", "es": "Direcciones permitidas de WireGuard"},
}

def listed_names(product):
    found = []
    seen = set()
    for _lot, names in lots[product]:
        for name in names:
            if name in seen:
                continue
            seen.add(name)
            found.append(name)
    return found

listed = {product: listed_names(product) for product in products}
used_names = {name for names in listed.values() for name in names}
missing_labels = sorted(used_names - set(labels))
unused_labels = sorted(set(labels) - used_names)
if missing_labels:
    die("label missing " + " ".join(missing_labels))
if unused_labels:
    die("label unused " + " ".join(unused_labels))
for name, texts in labels.items():
    if set(texts) != {"en", "fr", "de", "es"}:
        die(f"label languages {name}")
    for lang, text in texts.items():
        if not text or "\n" in text or text.startswith("["):
            die(f"label text {name} {lang}")

documents = {}
for product in products:
    parsed = []
    for filename in conf_names:
        path = root / product / "config" / filename
        parsed.extend(parse_conf(path, filename))
    seen = [item["name"] for item in parsed]
    if len(seen) != len(set(seen)):
        die(f"duplicate assignment {product}")
    known = set(rules[product])
    if set(seen) != known:
        missing = sorted(set(seen) - known)
        extra = sorted(known - set(seen))
        die(f"rule mismatch {product} missing={missing} extra={extra}")
    variables = [publish(product, item) for item in parsed]
    for variable in variables:
        if variable["file"] == "secrets.conf" and "default" in variable:
            die(f"secret default refused {variable['name']}")
    document = {
        "product": product,
        "pattern_engine": "bash",
        "allowed_references": allowed[product],
        "empty_default_references": ["INSTALL_DIRECTORY"],
        "forbidden": ["`", "$("],
        "files": [file_record(filename) for filename in conf_names],
        "variables": variables,
    }
    text = json.dumps(document, indent=2, ensure_ascii=False) + "\n"
    schema = "configuration.json"
    documents[f"{product}/config/schema/{schema}"] = text
    by_name = {item["name"]: item for item in variables}
    for list_mode in ("basic", "advanced"):
        rows = []
        for lot, names in lots[product]:
            for name in names:
                item = by_name[name]
                if list_mode == "basic" and item["file"] == "global.conf":
                    continue
                rows.append((lot, item["file"], name))
        buffer = io.StringIO()
        writer = csv.writer(buffer, lineterminator="\n")
        writer.writerow(("lot", "file", "name"))
        writer.writerows(rows)
        documents[f"config-{product}-{list_mode}.csv"] = buffer.getvalue()
label_names = []
seen_labels = set()
for product in products:
    for name in listed[product]:
        if name in seen_labels:
            continue
        seen_labels.add(name)
        label_names.append(name)
for lang in ("en", "fr", "de", "es"):
    blocks = [f"[LABEL_{name}]\n{labels[name][lang]}" for name in label_names]
    documents[f"share/locale/{lang}/label.txt"] = "\n\n".join(blocks) + "\n"

if mode == "check":
    stale = []
    for rel, text in documents.items():
        path = root / rel
        current = path.read_text(encoding="utf-8") if path.is_file() else None
        if current != text:
            stale.append(rel)
    if stale:
        die("stale " + " ".join(stale))
else:
    for rel, text in documents.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
