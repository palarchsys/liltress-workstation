#!/usr/bin/env python3
# =============================================================================
# File       : python/config-list.py
# Updated at : 2026-11-23
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Build the configuration schema from the product files.
# Note       : Check mode compares the documents and writes nothing.
# -----------------------------------------------------------------------------


import csv
import io
import json
import os
import re
import sys
from pathlib import Path


def load_schema_block_01_01():
    global root, mode, products, conf_names, assign_re, public_keys, profiles
    root = Path(os.environ["CONFIG_SCHEMA_ROOT"])
    mode = os.environ["CONFIG_SCHEMA_MODE"]
    products = ("workstation", "server")
    conf_names = ("global.conf", "user.conf", "secrets.conf")
    assign_re = re.compile(r"^([A-Z][A-Z0-9_]*)=(.*)$")
    public_keys = (
        "lot",
        "kind",
        "required",
        "empty_allowed",
        "choices",
        "pattern",
        "minimum",
        "maximum",
        "minimum_length",
        "maximum_length",
        "exclude",
        "forbidden",
        "reject",
        "separator",
        "mask_maximum",
        "port_minimum",
        "port_maximum",
        "equals",
        "distinct_from",
        "distinct_in",
        "when",
        "empty_when",
        "basic_fill",
        "computed",
        "resolves_to",
    )
    profiles = ["MATRIX", "LIVEKIT", "WIREGUARD"]


def load_schema_block_01_02():
    global excluded_users, mail_names, mail_when, mail_empty
    excluded_users = [
        "root",
        "daemon",
        "bin",
        "sys",
        "sync",
        "games",
        "man",
        "lp",
        "mail",
        "news",
        "uucp",
        "proxy",
        "www-data",
        "backup",
        "list",
        "irc",
        "nobody",
    ]
    mail_names = (
        "POSTFIX_SMTP_LOGIN",
        "POSTFIX_MAIL_ADDRESS",
        "POSTFIX_MAIL_PASSWORD",
        "POSTFIX_MAIL_SMTP",
        "WATCHDOG_MAIL",
    )
    mail_when = {"name": "MAIL_ALERTS", "value": "1"}
    mail_empty = {"name": "MAIL_ALERTS", "value": "0"}


def load_schema_block_01():
    load_schema_block_01_01()
    load_schema_block_01_02()


load_schema_block_01()


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


def collect_asked_names(groups):
    names = []
    for _lot, grouped in groups:
        names.extend(grouped)
    return names


def check_asked_unique(product, names):
    if len(names) != len(set(names)):
        die(f"duplicate list name in {product}")


def check_asked_known(product, names):
    for name in names:
        if name not in rules[product] or not rules[product][name]["ask"]:
            die(f"list name is not a parameter {product} {name}")


def check_asked_complete(product, names):
    for name, rule in rules[product].items():
        if rule["ask"] and name not in names:
            die(f"parameter missing from lists {product} {name}")


def check_asked_lists():
    global asked
    asked = {}
    for product, groups in lots.items():
        names = collect_asked_names(groups)
        check_asked_unique(product, names)
        asked[product] = names
        check_asked_known(product, names)
        check_asked_complete(product, names)


def load_schema_block_02_01():
    global email, user_name, hostname, absolute, project_name, project_version, languages, banner
    global template_name, pro_token, tailscale_key
    email = shaped("email", r"^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$", required=True)
    user_name = shaped(
        "user",
        r"^[a-z_][a-z0-9_-]{0,31}$",
        required=True,
        exclude=excluded_users,
    )
    hostname = shaped(
        "hostname",
        r"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$",
        required=True,
    )
    absolute = shaped(
        "path",
        r"^/[A-Za-z0-9._/-]+$",
        required=True,
        reject=[".."],
    )
    project_name = shaped(
        "pattern",
        r"^[A-Za-z0-9][A-Za-z0-9 ._-]{0,62}$",
        required=True,
    )
    project_version = shaped(
        "pattern",
        r"^[0-9]+(\.[0-9]+){0,2}$",
        required=True,
    )
    languages = choice(("en", "fr", "de", "es"))
    banner = {"kind": "text", "required": True, "forbidden": ["$(", "`"]}
    template_name = shaped(
        "pattern",
        r"^[A-Za-z0-9][A-Za-z0-9._-]*\.html$",
        required=True,
    )
    pro_token = shaped("secret", r"^[A-Za-z0-9]{6,100}$", required=True)
    tailscale_key = shaped("secret", r"^tskey-auth-[A-Za-z0-9_-]{10,200}$", required=True)


def load_schema_block_02_02():
    global secret_value, turnstile, smtp, watchdog_cpu, watchdog_nice, watchdog_io
    secret_value = shaped(
        "secret",
        r"^[A-Za-z0-9@#%+=:./_-]{16,128}$",
        required=True,
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
    put_both("TAILSCALE_AUTH_KEY", "token", True, tailscale_key)
    put(
        "server",
        "UBUNTU_PRO_TOKEN",
        "token",
        True,
        shaped(
            "secret",
            r"^[A-Za-z0-9]{6,100}$",
            empty_allowed=True,
        ),
    )
    put_both("POSTFIX_SMTP_LOGIN", "mail", True, mail_rule("email", pattern=email["pattern"]))
    put_both("POSTFIX_MAIL_ADDRESS", "mail", True, mail_rule("email", pattern=email["pattern"]))


def load_schema_block_02_03():
    put_both(
        "POSTFIX_MAIL_PASSWORD",
        "mail",
        True,
        mail_rule(
            "secret",
            **{
                "minimum_length": 8,
                "maximum_length": 128,
                "forbidden": [" ", '"', "'", "$", "\\", "`"],
            },
        ),
    )
    put_both(
        "POSTFIX_MAIL_SMTP",
        "mail",
        True,
        mail_rule(
            "smtp",
            pattern=smtp["pattern"],
            port_minimum=1,
            port_maximum=65535,
            reject=[".."],
        ),
    )
    put_both(
        "WATCHDOG_MAIL",
        "mail",
        True,
        mail_rule(
            "email",
            pattern=email["pattern"],
            equals="POSTFIX_MAIL_ADDRESS",
        ),
    )
    put_both("CONFIG_PREPARED", "prepared", False, choice(("1",), required=True))
    put_both("SECRET_PREPARED", "prepared", False, choice(("1",), required=True))
    put_both("BANNER_MESSAGE", "banner", True, banner)
    put_both("SSH_BANNER_PATH", "banner", True, absolute)


def load_schema_block_02_04():
    put_both("MAIL_TEMPLATE", "template", True, template_name)
    put_both("WATCHDOG_CPU_LIMIT", "watchdog", True, watchdog_cpu)
    put_both("WATCHDOG_LIMIT_NICE", "watchdog", True, watchdog_nice)
    put_both("WATCHDOG_LIMIT_IO_NICE", "watchdog", True, watchdog_io)
    put("workstation", "PROJECT_VERSION", "identity", True, project_version)
    put("server", "PROJECT_VERSION", "version", True, project_version)
    put("workstation", "PROJECT_NAME", "identity", True, project_name)
    put(
        "workstation",
        "PROJECT_SLUG",
        "identity",
        True,
        choice(
            ("liltress-workstation",),
            required=True,
        ),
    )
    put(
        "workstation",
        "CONFIG_BASE_DIRECTORY",
        "paths",
        True,
        choice(
            ("/opt/liltress-workstation",),
            required=True,
        ),
    )
    put(
        "workstation",
        "SECRET_DIRECTORY",
        "paths",
        False,
        {
            "kind": "template",
            "computed": True,
            "resolves_to": "/opt/liltress-workstation/secrets",
        },
    )
    put("workstation", "LYNIS_MIN_SCORE", "audit", True, integer(0, 100, required=True))


def load_schema_block_02_05():
    put("workstation", "SSH_SERVICE_NAME", "ssh", True, choice(("ssh",), required=True))
    put("workstation", "SSH_MAX_AUTH_TRIES", "ssh", True, integer(1, 10, required=True))
    put("workstation", "SSH_CLIENT_ALIVE_INTERVAL", "ssh", True, integer(30, 3600, required=True))
    put("workstation", "SSH_CLIENT_ALIVE_COUNT_MAX", "ssh", True, integer(0, 10, required=True))
    put("workstation", "SSH_TCP_KEEPALIVE", "ssh", True, choice(("yes", "no"), required=True))
    put("workstation", "SSH_MAX_SESSIONS", "ssh", True, integer(1, 10, required=True))
    put("workstation", "SSH_USER", "account", True, user_name)
    put("workstation", "SSH_GROUP", "account", True, user_name)
    put(
        "workstation",
        "SSH_PORT",
        "account",
        True,
        integer(1024, 65535, required=True),
    )
    put("workstation", "SSH_LOGIN_GRACE_TIME", "ssh", True, integer(10, 120, required=True))
    put("workstation", "PAM_PASSWORD_MIN_LENGTH", "pam", True, integer(8, 32, required=True))
    put("workstation", "FAILLOCK_DENY", "pam", True, integer(3, 20, required=True))
    put("workstation", "FAILLOCK_UNLOCK", "pam", True, integer(60, 86400, required=True))
    put("workstation", "FAILLOCK_FAIL_INTERVAL", "pam", True, integer(60, 86400, required=True))
    put("server", "PROJECT_NAME", "site", True, project_name)
    put(
        "server",
        "DOMAIN",
        "site",
        True,
        shaped(
            "domain",
            r"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$",
            required=True,
        ),
    )
    put("server", "MAIN_USER", "account", True, {**user_name, "distinct_from": ["CRON_USER"]})
    put("server", "MAIN_GROUP", "account", True, user_name)


def load_schema_block_02_06():
    put(
        "server",
        "SSH_PORT",
        "account",
        True,
        integer(
            1024,
            65535,
            required=True,
            distinct_in=list(profiles),
        ),
    )
    put("server", "MODE_TEST", "mode", True, flag())
    put("server", "MODE_DEV", "mode", True, flag())
    put("server", "LYNIS_MIN_SCORE", "audit", True, integer(0, 100, required=True))
    put("server", "NGINX_CERTBOT_MAIL_ADDRESS", "certificate", True, email)
    put("server", "ANTIBOT_HMAC_SECRET", "web-secret", True, {**secret_value, "basic_fill": "hex-32"})
    put("server", "POSTGRES_WEB_PASSWORD", "web-secret", True, {**secret_value, "basic_fill": "hex-32"})
    put("server", "TURNSTILE_SITE_KEY", "web-secret", True, {**turnstile, "basic_fill": "turnstile-site"})
    put("server", "TURNSTILE_SECRET_KEY", "web-secret", True, {**turnstile, "basic_fill": "turnstile-secret"})
    put("server", "CONFIG_BASE_DIRECTORY", "paths", True, choice(("/opt/liltress-server",), required=True))
    put(
        "server",
        "SECRET_DIRECTORY",
        "paths",
        False,
        {
            "kind": "template",
            "computed": True,
            "resolves_to": "/opt/liltress-server/secrets",
        },
    )


def load_schema_block_02_07():
    put(
        "server",
        "DOCKER_BASE_DIRECTORY",
        "paths",
        False,
        {
            "kind": "template",
            "computed": True,
            "resolves_to": "/opt/liltress-server/docker",
        },
    )
    put(
        "server",
        "SSH_SERVICE_NAME",
        "ssh",
        True,
        shaped(
            "pattern",
            r"^[a-z][a-z0-9-]*$",
            required=True,
        ),
    )
    put("server", "SSH_MAX_AUTH_TRIES", "ssh", True, integer(1, 10, required=True))
    put("server", "SSH_CLIENT_ALIVE_INTERVAL", "ssh", True, integer(0, 3600, required=True))
    put("server", "SSH_CLIENT_ALIVE_COUNT_MAX", "ssh", True, integer(0, 10, required=True))
    put("server", "SSH_LOGIN_GRACE_TIME", "ssh", True, integer(10, 120, required=True))
    put("server", "SSH_TCP_KEEPALIVE", "ssh", True, choice(("yes", "no"), required=True))
    put("server", "SSH_MAX_SESSIONS", "ssh", True, integer(1, 10, required=True))
    put("server", "FAILLOCK_DENY", "pam", True, integer(3, 20, required=True))
    put("server", "FAILLOCK_UNLOCK", "pam", True, integer(60, 86400, required=True))
    put("server", "FAILLOCK_FAIL_INTERVAL", "pam", True, integer(60, 86400, required=True))


def load_schema_block_02_08():
    global host_name
    put(
        "server",
        "UNBOUND_FORWARDERS",
        "resolver",
        True,
        {
            "kind": "ipv4-list",
            "separator": " ",
            "pattern": r"^([0-9]{1,3}\.){3}[0-9]{1,3}$",
            "required": True,
        },
    )
    put("server", "USBGUARD_ENABLE", "resolver", True, flag())
    put("server", "DDOS_HARDENING_LEVEL", "resolver", True, choice(("1", "2", "3"), required=True))
    for host_name in ("HOSTNAME_MATRIX", "HOSTNAME_LIVEKIT", "HOSTNAME_WIREGUARD"):
        put("server", host_name, "hosts", True, hostname)
    put(
        "server",
        "SWAP_SIZE",
        "swap",
        True,
        shaped(
            "pattern",
            r"^[1-9][0-9]*[KMGT]$",
            required=True,
        ),
    )
    put("server", "SWAP_FILE", "swap", True, absolute)


def load_schema_block_02_09():
    put(
        "server",
        "SWAP_MAPPER_NAME",
        "swap",
        True,
        shaped(
            "pattern",
            r"^[a-z][a-z0-9_-]{0,31}$",
            required=True,
        ),
    )
    put("server", "CRON_USER", "cron", True, {**user_name, "distinct_from": ["MAIN_USER"]})
    put("server", "NGINX_ADMIN_USER", "nginx", True, user_name)
    put(
        "server",
        "NGINX_HTPASSWD_PATH",
        "nginx",
        True,
        shaped(
            "path",
            r"^/[A-Za-z0-9._/-]+$",
            required=True,
        ),
    )
    put(
        "server",
        "NGINX_HTPASSWD_REALM",
        "nginx",
        True,
        {
            "kind": "text",
            "required": True,
            "forbidden": ['"', "$"],
        },
    )


def load_schema_block_02_10():
    put(
        "server",
        "DOCKER_NETWORK_PRODUCTION",
        "docker-network",
        True,
        shaped(
            "cidr",
            r"^([0-9.]+)/([0-9]+)$",
            required=True,
            mask_maximum=32,
            distinct_from=["DOCKER_NETWORK_SECURITY"],
        ),
    )
    put(
        "server",
        "DOCKER_NETWORK_SECURITY",
        "docker-network",
        True,
        shaped(
            "cidr",
            r"^([0-9.]+)/([0-9]+)$",
            required=True,
            mask_maximum=32,
            distinct_from=["DOCKER_NETWORK_PRODUCTION"],
        ),
    )
    put(
        "server",
        "DOCKER_LOG_DRIVER",
        "docker-log",
        True,
        choice(
            ("local", "json-file", "journald"),
            required=True,
        ),
    )


def load_schema_block_02_11():
    global database_name
    put(
        "server",
        "DOCKER_LOG_MAX_SIZE",
        "docker-log",
        True,
        shaped(
            "pattern",
            r"^[1-9][0-9]*[kmgKMG]?$",
            required=True,
        ),
    )
    put("server", "DOCKER_LOG_MAX_FILE", "docker-log", True, integer(1, 20, required=True))
    put("server", "DOCKER_LOG_COMPRESS", "docker-log", True, choice(("true", "false"), required=True))
    for database_name in (
        "POSTGRES_SYNAPSE_USER",
        "POSTGRES_SYNAPSE_DB",
        "POSTGRES_KEYCLOAK_USER",
        "POSTGRES_KEYCLOAK_DB",
        "POSTGRES_WEB_USER",
        "POSTGRES_WEB_DB",
    ):
        put(
            "server",
            database_name,
            "postgres",
            True,
            shaped(
                "pattern",
                r"^[a-z][a-z0-9_]{0,30}$",
                required=True,
            ),
        )


def load_schema_block_02_12():
    global server_ports, port_name, port_profiles
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
        put(
            "server",
            port_name,
            "ports",
            True,
            integer(
                1,
                65535,
                required=True,
                distinct_in=list(port_profiles),
            ),
        )


def load_schema_block_02_13():
    put(
        "server",
        "WEB_REGISTRY",
        "web",
        True,
        shaped(
            "pattern",
            r"^[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]+)?(/[a-z0-9._-]+)+$",
            required=True,
        ),
    )
    put(
        "server",
        "WEB_IMAGE_FRONTEND",
        "web",
        True,
        shaped(
            "pattern",
            r"^[a-z0-9][a-z0-9._-]{0,80}$",
            required=True,
        ),
    )
    put(
        "server",
        "WEB_IMAGE_BACKEND",
        "web",
        True,
        shaped(
            "pattern",
            r"^[a-z0-9][a-z0-9._-]{0,80}$",
            required=True,
        ),
    )


def load_schema_block_02_14():
    put(
        "server",
        "WEB_IMAGE_TAG",
        "web",
        True,
        shaped(
            "pattern",
            r"^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$",
            required=True,
        ),
    )
    put(
        "server",
        "WEB_UPDATE_SCRIPT",
        "web",
        True,
        shaped(
            "path",
            r"^/usr/local/bin/[A-Za-z0-9._-]+$",
            required=True,
        ),
    )
    put(
        "server",
        "MATRIX_ADMIN_USER",
        "matrix",
        True,
        shaped(
            "pattern",
            r"^[a-z][a-z0-9_-]{2,31}$",
            required=True,
        ),
    )


def load_schema_block_02_15():
    put(
        "server",
        "KEYCLOAK_REALM",
        "keycloak",
        True,
        shaped(
            "pattern",
            r"^[a-z][a-z0-9-]{1,62}$",
            required=True,
        ),
    )
    put(
        "server",
        "KEYCLOAK_CLIENT",
        "keycloak",
        True,
        shaped(
            "pattern",
            r"^[a-z][a-z0-9-]{1,62}$",
            required=True,
        ),
    )
    put(
        "server",
        "KC_BOOTSTRAP_ADMIN_USERNAME",
        "keycloak",
        True,
        shaped(
            "pattern",
            r"^[a-z][a-z0-9_-]{2,31}$",
            required=True,
        ),
    )


def load_schema_block_02_16():
    put(
        "server",
        "WIREGUARD_DEFAULT_DNS",
        "wireguard",
        True,
        shaped(
            "pattern",
            r"^[0-9.]+(,[0-9.]+)*$",
            required=True,
        ),
    )
    put(
        "server",
        "WIREGUARD_DEFAULT_ADDRESS",
        "wireguard",
        True,
        shaped(
            "pattern",
            r"^([0-9]{1,3}\.){3}x$",
            required=True,
        ),
    )
    put(
        "server",
        "WIREGUARD_ALLOWED_IP",
        "wireguard",
        True,
        shaped(
            "pattern",
            r"^[0-9a-fA-F.:/,]+$",
            required=True,
        ),
    )


def load_schema_block_02_17():
    global derived_paths, derived_name, resolved, lot_name
    derived_paths = {
        "DOCKER_DIRECTORY_MATRIX": "/opt/liltress-server/docker/matrix",
        "DOCKER_DIRECTORY_LIVEKIT": "/opt/liltress-server/docker/livekit",
        "DOCKER_DIRECTORY_WIREGUARD": "/opt/liltress-server/docker/wireguard",
        "DOCKER_DIRECTORY_SECURITY": "/opt/liltress-server/docker/security",
        "ENV_FILE_MATRIX": "/opt/liltress-server/secrets/matrix.env",
        "ENV_FILE_LIVEKIT": "/opt/liltress-server/secrets/livekit.env",
        "ENV_FILE_WIREGUARD": "/opt/liltress-server/secrets/wireguard.env",
        "ENV_FILE_SECURITY": "/opt/liltress-server/secrets/security.env",
        "ENV_FILE_WEB": "/opt/liltress-server/secrets/web.env",
    }
    for derived_name, resolved in derived_paths.items():
        lot_name = "paths"
        put(
            "server",
            derived_name,
            lot_name,
            False,
            {
                "kind": "template",
                "computed": True,
                "resolves_to": resolved,
            },
        )


def load_schema_block_02_18():
    global derived_name
    for derived_name in (
        "DOMAIN_SYNAPSE",
        "DOMAIN_ELEMENT",
        "DOMAIN_SYNAPSE_ADMIN",
        "DOMAIN_PROMETHEUS",
        "DOMAIN_KEYCLOAK",
        "DOMAIN_LIVEKIT_JWT",
        "DOMAIN_LIVEKIT_SFU",
        "DOMAIN_WIREGUARD",
        "DOMAIN_WEB_API",
        "MATRIX_SERVER_NAME",
        "MATRIX_PUBLIC_BASE_URL",
        "ELEMENT_PUBLIC_BASE_URL",
        "KEYCLOAK_PUBLIC_BASE_URL",
    ):
        put("server", derived_name, "domain", False, {"kind": "template", "computed": True})
    add_lot("workstation", "language", ["LANGUAGE"])
    add_lot("workstation", "token", ["UBUNTU_PRO_TOKEN", "TAILSCALE_AUTH_KEY"])
    add_lot("workstation", "account", ["SSH_USER", "SSH_GROUP", "SSH_PORT"])
    add_lot("workstation", "alerts", ["MAIL_ALERTS"])
    add_lot("workstation", "mail", mail_names)
    add_lot("workstation", "identity", ["PROJECT_NAME", "PROJECT_SLUG", "PROJECT_VERSION"])
    add_lot("workstation", "paths", ["CONFIG_BASE_DIRECTORY"])
    add_lot("workstation", "audit", ["LYNIS_MIN_SCORE"])
    add_lot("workstation", "banner", ["BANNER_MESSAGE", "SSH_BANNER_PATH"])
    add_lot(
        "workstation",
        "ssh",
        [
            "SSH_SERVICE_NAME",
            "SSH_MAX_AUTH_TRIES",
            "SSH_CLIENT_ALIVE_INTERVAL",
            "SSH_CLIENT_ALIVE_COUNT_MAX",
            "SSH_LOGIN_GRACE_TIME",
            "SSH_TCP_KEEPALIVE",
            "SSH_MAX_SESSIONS",
        ],
    )


def load_schema_block_02_19():
    add_lot(
        "workstation",
        "watchdog",
        [
            "WATCHDOG_CPU_LIMIT",
            "WATCHDOG_LIMIT_NICE",
            "WATCHDOG_LIMIT_IO_NICE",
        ],
    )
    add_lot("workstation", "template", ["MAIL_TEMPLATE"])
    add_lot(
        "workstation",
        "pam",
        [
            "PAM_PASSWORD_MIN_LENGTH",
            "FAILLOCK_DENY",
            "FAILLOCK_UNLOCK",
            "FAILLOCK_FAIL_INTERVAL",
        ],
    )
    add_lot("server", "language", ["LANGUAGE"])
    add_lot("server", "site", ["PROJECT_NAME", "DOMAIN"])
    add_lot("server", "account", ["MAIN_USER", "MAIN_GROUP", "SSH_PORT"])
    add_lot("server", "token", ["UBUNTU_PRO_TOKEN", "TAILSCALE_AUTH_KEY"])
    add_lot("server", "pam", ["FAILLOCK_DENY", "FAILLOCK_UNLOCK", "FAILLOCK_FAIL_INTERVAL"])
    add_lot("server", "mode", ["MODE_TEST", "MODE_DEV"])
    add_lot("server", "audit", ["LYNIS_MIN_SCORE"])
    add_lot("server", "alerts", ["MAIL_ALERTS"])
    add_lot("server", "mail", mail_names)
    add_lot("server", "certificate", ["NGINX_CERTBOT_MAIL_ADDRESS"])


def load_schema_block_02_20():
    add_lot(
        "server",
        "web-secret",
        [
            "ANTIBOT_HMAC_SECRET",
            "POSTGRES_WEB_PASSWORD",
            "TURNSTILE_SITE_KEY",
            "TURNSTILE_SECRET_KEY",
        ],
    )
    add_lot("server", "version", ["PROJECT_VERSION"])
    add_lot("server", "paths", ["CONFIG_BASE_DIRECTORY"])
    add_lot("server", "banner", ["BANNER_MESSAGE", "SSH_BANNER_PATH"])
    add_lot(
        "server",
        "ssh",
        [
            "SSH_SERVICE_NAME",
            "SSH_MAX_AUTH_TRIES",
            "SSH_CLIENT_ALIVE_INTERVAL",
            "SSH_CLIENT_ALIVE_COUNT_MAX",
            "SSH_LOGIN_GRACE_TIME",
            "SSH_TCP_KEEPALIVE",
            "SSH_MAX_SESSIONS",
        ],
    )
    add_lot(
        "server",
        "watchdog",
        [
            "WATCHDOG_CPU_LIMIT",
            "WATCHDOG_LIMIT_NICE",
            "WATCHDOG_LIMIT_IO_NICE",
        ],
    )
    add_lot("server", "template", ["MAIL_TEMPLATE"])
    add_lot("server", "resolver", ["UNBOUND_FORWARDERS", "USBGUARD_ENABLE", "DDOS_HARDENING_LEVEL"])
    add_lot("server", "hosts", ["HOSTNAME_MATRIX", "HOSTNAME_LIVEKIT", "HOSTNAME_WIREGUARD"])
    add_lot("server", "swap", ["SWAP_SIZE", "SWAP_FILE", "SWAP_MAPPER_NAME"])


def load_schema_block_02_21():
    add_lot("server", "cron", ["CRON_USER"])
    add_lot("server", "nginx", ["NGINX_ADMIN_USER", "NGINX_HTPASSWD_PATH", "NGINX_HTPASSWD_REALM"])
    add_lot("server", "docker-network", ["DOCKER_NETWORK_PRODUCTION", "DOCKER_NETWORK_SECURITY"])
    add_lot(
        "server",
        "docker-log",
        [
            "DOCKER_LOG_DRIVER",
            "DOCKER_LOG_MAX_SIZE",
            "DOCKER_LOG_MAX_FILE",
            "DOCKER_LOG_COMPRESS",
        ],
    )
    add_lot(
        "server",
        "postgres",
        [
            "POSTGRES_SYNAPSE_USER",
            "POSTGRES_SYNAPSE_DB",
            "POSTGRES_KEYCLOAK_USER",
            "POSTGRES_KEYCLOAK_DB",
            "POSTGRES_WEB_USER",
            "POSTGRES_WEB_DB",
        ],
    )
    add_lot("server", "ports", list(server_ports))
    add_lot(
        "server",
        "web",
        [
            "WEB_REGISTRY",
            "WEB_IMAGE_FRONTEND",
            "WEB_IMAGE_BACKEND",
            "WEB_IMAGE_TAG",
            "WEB_UPDATE_SCRIPT",
        ],
    )
    add_lot("server", "matrix", ["MATRIX_ADMIN_USER"])
    add_lot("server", "keycloak", ["KEYCLOAK_REALM", "KEYCLOAK_CLIENT", "KC_BOOTSTRAP_ADMIN_USERNAME"])


def load_schema_block_02_22():
    global asked
    add_lot(
        "server",
        "wireguard",
        [
            "WIREGUARD_DEFAULT_DNS",
            "WIREGUARD_DEFAULT_ADDRESS",
            "WIREGUARD_ALLOWED_IP",
        ],
    )
    asked = {}


def load_schema_block_02():
    load_schema_block_02_01()
    load_schema_block_02_02()
    load_schema_block_02_03()
    load_schema_block_02_04()
    load_schema_block_02_05()
    load_schema_block_02_06()
    load_schema_block_02_07()
    load_schema_block_02_08()
    load_schema_block_02_09()
    load_schema_block_02_10()
    load_schema_block_02_11()
    load_schema_block_02_12()
    load_schema_block_02_13()
    load_schema_block_02_14()
    load_schema_block_02_15()
    load_schema_block_02_16()
    load_schema_block_02_17()
    load_schema_block_02_18()
    load_schema_block_02_19()
    load_schema_block_02_20()
    load_schema_block_02_21()
    load_schema_block_02_22()
    check_asked_lists()


load_schema_block_02()


def open_quote(raw):
    return raw.startswith('"') and not raw.endswith('"')


def closed_quote(raw):
    return len(raw) >= 2 and raw.startswith('"') and raw.endswith('"')


def read_value(lines, cursor, filename, name, raw):
    if not open_quote(raw):
        return raw, cursor
    parts = [raw]
    cursor += 1
    while cursor < len(lines):
        parts.append(lines[cursor])
        if lines[cursor].endswith('"'):
            break
        cursor += 1
    else:
        die(f"unclosed value in {filename} {name}")
    return "\n".join(parts), cursor


def plain_value(filename, raw):
    if filename == "secrets.conf":
        return None
    if closed_quote(raw):
        return raw[1:-1]
    return raw


def one_assignment(lines, cursor, filename):
    found = assign_re.match(lines[cursor])
    if not found:
        return None, cursor + 1
    name, raw = found.group(1), found.group(2)
    raw, cursor = read_value(lines, cursor, filename, name, raw)
    item = {
        "name": name,
        "file": filename,
        "computed": "${" in raw,
        "value": plain_value(filename, raw),
    }
    return item, cursor + 1


def parse_conf(path, filename):
    lines = path.read_text(encoding="utf-8").splitlines()
    found = []
    cursor = 0
    while cursor < len(lines):
        item, cursor = one_assignment(lines, cursor, filename)
        if item is not None:
            found.append(item)
    return found


def copy_public(product, item):
    rule = rules[product][item["name"]]
    if bool(rule.get("computed")) != item["computed"]:
        die(f"computed flag differs {product} {item['name']}")
    body = {"name": item["name"], "file": item["file"]}
    for key in public_keys:
        if key in rule:
            body[key] = rule[key]
    return rule, body


def refuse_secret(item, body):
    if item["file"] != "secrets.conf":
        return False
    if "default" in body:
        die(f"secret default refused {item['name']}")
    return True


def integer_default(product, item, rule, body):
    value = item["value"]
    if not re.fullmatch(r"[0-9]+", value or ""):
        die(f"integer default refused {product} {item['name']}")
    number = int(value)
    if number < rule["minimum"] or number > rule["maximum"]:
        die(f"integer default outside range {product} {item['name']}")
    body["default"] = number


def choice_default(product, item, rule, body):
    value = item["value"]
    text = "" if value is None else str(value)
    if text not in rule["choices"]:
        die(f"choice default refused {product} {item['name']}")
    body["default"] = text


def put_default(product, item, rule, body):
    if rule["kind"] == "integer":
        integer_default(product, item, rule, body)
        return
    if rule["kind"] == "choice":
        choice_default(product, item, rule, body)
        return
    body["default"] = item["value"]


def publish(product, item):
    rule, body = copy_public(product, item)
    if refuse_secret(item, body):
        return body
    put_default(product, item, rule, body)
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


def load_schema_block_03_labels_01():
    return {
        "LANGUAGE": {"en": "Language", "fr": "Langue", "de": "Sprache", "es": "Idioma"},
        "UBUNTU_PRO_TOKEN": {
            "en": "Ubuntu Pro token",
            "fr": "Jeton Ubuntu Pro",
            "de": "Ubuntu-Pro-Token",
            "es": "Token de Ubuntu Pro",
        },
    }


def load_schema_block_03_labels_02():
    return {
        "MAIL_ALERTS": {
            "en": "Email alerts",
            "fr": "Alertes e-mail",
            "de": "E-Mail-Alarme",
            "es": "Alertas por correo",
        },
        "POSTFIX_SMTP_LOGIN": {
            "en": "SMTP login",
            "fr": "Identifiant SMTP",
            "de": "SMTP-Anmeldung",
            "es": "Usuario SMTP",
        },
        "POSTFIX_MAIL_ADDRESS": {
            "en": "Sender email address",
            "fr": "Adresse e-mail de l'expéditeur",
            "de": "Absender-E-Mail-Adresse",
            "es": "Correo del remitente",
        },
    }


def load_schema_block_03_labels_03():
    return {
        "POSTFIX_MAIL_PASSWORD": {
            "en": "SMTP password",
            "fr": "Mot de passe SMTP",
            "de": "SMTP-Passwort",
            "es": "Contraseña SMTP",
        },
    }


def load_schema_block_03_labels_04():
    return {
        "POSTFIX_MAIL_SMTP": {"en": "SMTP server", "fr": "Serveur SMTP", "de": "SMTP-Server", "es": "Servidor SMTP"},
        "WATCHDOG_MAIL": {
            "en": "Alert recipient",
            "fr": "Destinataire des alertes",
            "de": "Empfänger der Alarme",
            "es": "Destinatario de las alertas",
        },
    }


def load_schema_block_03_labels_05():
    return {
        "PROJECT_NAME": {"en": "Project name", "fr": "Nom du projet", "de": "Projektname", "es": "Nombre del proyecto"},
        "PROJECT_SLUG": {
            "en": "Project identifier",
            "fr": "Identifiant du projet",
            "de": "Projektkennung",
            "es": "Identificador del proyecto",
        },
    }


def load_schema_block_03_labels_06():
    return {
        "PROJECT_VERSION": {
            "en": "Project version",
            "fr": "Version du projet",
            "de": "Projektversion",
            "es": "Versión del proyecto",
        },
    }


def load_schema_block_03_labels_07():
    return {
        "CONFIG_BASE_DIRECTORY": {
            "en": "Install directory",
            "fr": "Répertoire d'installation",
            "de": "Installationsverzeichnis",
            "es": "Directorio de instalación",
        },
    }


def load_schema_block_03_labels_08():
    return {
        "LYNIS_MIN_SCORE": {
            "en": "Minimum Lynis score",
            "fr": "Score Lynis minimal",
            "de": "Minimaler Lynis-Wert",
            "es": "Puntuación mínima de Lynis",
        },
    }


def load_schema_block_03_labels_09():
    return {
        "BANNER_MESSAGE": {
            "en": "Login banner",
            "fr": "Bannière de connexion",
            "de": "Anmeldebanner",
            "es": "Banner de inicio de sesión",
        },
    }


def load_schema_block_03_labels_10():
    return {
        "SSH_BANNER_PATH": {
            "en": "SSH banner file",
            "fr": "Fichier de la bannière SSH",
            "de": "SSH-Bannerdatei",
            "es": "Archivo del banner SSH",
        },
    }


def load_schema_block_03_labels_11():
    return {
        "SSH_SERVICE_NAME": {
            "en": "SSH service name",
            "fr": "Nom du service SSH",
            "de": "Name des SSH-Dienstes",
            "es": "Nombre del servicio SSH",
        },
    }


def load_schema_block_03_labels_12():
    return {
        "SSH_MAX_AUTH_TRIES": {
            "en": "Maximum SSH authentication tries",
            "fr": "Essais d'authentification SSH",
            "de": "Maximale SSH-Anmeldeversuche",
            "es": "Intentos máximos de autenticación SSH",
        },
    }


def load_schema_block_03_labels_13():
    return {
        "SSH_CLIENT_ALIVE_INTERVAL": {
            "en": "SSH keepalive interval",
            "fr": "Intervalle de maintien SSH",
            "de": "SSH-Keepalive-Intervall",
            "es": "Intervalo de keepalive SSH",
        },
    }


def load_schema_block_03_labels_14():
    return {
        "SSH_CLIENT_ALIVE_COUNT_MAX": {
            "en": "SSH keepalive count",
            "fr": "Nombre de maintiens SSH",
            "de": "SSH-Keepalive-Anzahl",
            "es": "Número de keepalives SSH",
        },
    }


def load_schema_block_03_labels_15():
    return {
        "SSH_LOGIN_GRACE_TIME": {
            "en": "SSH login grace time",
            "fr": "Délai de connexion SSH",
            "de": "SSH-Anmeldefrist",
            "es": "Tiempo de gracia de conexión SSH",
        },
    }


def load_schema_block_03_labels_16():
    return {
        "WATCHDOG_CPU_LIMIT": {
            "en": "Watchdog CPU limit",
            "fr": "Limite CPU du contrôle",
            "de": "CPU-Limit der Überwachung",
            "es": "Límite de CPU del control",
        },
    }


def load_schema_block_03_labels_17():
    return {
        "WATCHDOG_LIMIT_NICE": {
            "en": "Watchdog CPU priority",
            "fr": "Priorité CPU du contrôle",
            "de": "CPU-Priorität der Überwachung",
            "es": "Prioridad de CPU del control",
        },
    }


def load_schema_block_03_labels_18():
    return {
        "WATCHDOG_LIMIT_IO_NICE": {
            "en": "Watchdog disk priority",
            "fr": "Priorité disque du contrôle",
            "de": "Festplattenpriorität der Überwachung",
            "es": "Prioridad de disco del control",
        },
    }


def load_schema_block_03_labels_19():
    return {
        "MAIL_TEMPLATE": {
            "en": "Mail template",
            "fr": "Modèle de courrier",
            "de": "E-Mail-Vorlage",
            "es": "Plantilla de correo",
        },
    }


def load_schema_block_03_labels_20():
    return {
        "PAM_PASSWORD_MIN_LENGTH": {
            "en": "Minimum password length",
            "fr": "Longueur minimale du mot de passe",
            "de": "Minimale Passwortlänge",
            "es": "Longitud mínima de la contraseña",
        },
    }


def load_schema_block_03_labels_21():
    return {
        "FAILLOCK_DENY": {
            "en": "Failed attempts before lock",
            "fr": "Essais avant verrouillage",
            "de": "Versuche vor der Sperre",
            "es": "Intentos antes del bloqueo",
        },
    }


def load_schema_block_03_labels_22():
    return {
        "FAILLOCK_UNLOCK": {
            "en": "Lock duration",
            "fr": "Durée du verrouillage",
            "de": "Sperrdauer",
            "es": "Duración del bloqueo",
        },
    }


def load_schema_block_03_labels_23():
    return {
        "FAILLOCK_FAIL_INTERVAL": {
            "en": "Failed-attempt window",
            "fr": "Fenêtre des essais échoués",
            "de": "Zeitfenster der Fehlversuche",
            "es": "Ventana de intentos fallidos",
        },
    }


def load_schema_block_03_labels_24():
    return {
        "DOMAIN": {"en": "Domain name", "fr": "Nom de domaine", "de": "Domainname", "es": "Nombre de dominio"},
        "MAIN_USER": {"en": "Main account", "fr": "Compte principal", "de": "Hauptkonto", "es": "Cuenta principal"},
        "MAIN_GROUP": {"en": "Main group", "fr": "Groupe principal", "de": "Hauptgruppe", "es": "Grupo principal"},
        "SSH_PORT": {"en": "SSH port", "fr": "Port SSH", "de": "SSH-Port", "es": "Puerto SSH"},
        "SSH_USER": {"en": "SSH account", "fr": "Compte SSH", "de": "SSH-Konto", "es": "Cuenta SSH"},
        "SSH_GROUP": {"en": "SSH group", "fr": "Groupe SSH", "de": "SSH-Gruppe", "es": "Grupo SSH"},
    }


def load_schema_block_03_labels_25():
    return {
        "SSH_TCP_KEEPALIVE": {
            "en": "SSH TCP keepalive",
            "fr": "Maintien TCP SSH",
            "de": "SSH-TCP-Keepalive",
            "es": "Keepalive TCP de SSH",
        },
    }


def load_schema_block_03_labels_26():
    return {
        "SSH_MAX_SESSIONS": {
            "en": "SSH session limit",
            "fr": "Nombre de sessions SSH",
            "de": "SSH-Sitzungslimit",
            "es": "Límite de sesiones SSH",
        },
    }


def load_schema_block_03_labels_27():
    return {
        "TAILSCALE_AUTH_KEY": {
            "en": "Tailscale auth key",
            "fr": "Clé d'authentification Tailscale",
            "de": "Tailscale-Authentifizierungsschlüssel",
            "es": "Clave de autenticación de Tailscale",
        },
    }


def load_schema_block_03_labels_28():
    return {
        "MODE_TEST": {"en": "Test mode", "fr": "Mode test", "de": "Testmodus", "es": "Modo de prueba"},
        "MODE_DEV": {
            "en": "Development mode",
            "fr": "Mode développement",
            "de": "Entwicklungsmodus",
            "es": "Modo de desarrollo",
        },
    }


def load_schema_block_03_labels_29():
    return {
        "NGINX_CERTBOT_MAIL_ADDRESS": {
            "en": "Certificate email address",
            "fr": "Adresse e-mail du certificat",
            "de": "E-Mail-Adresse des Zertifikats",
            "es": "Correo del certificado",
        },
    }


def load_schema_block_03_labels_30():
    return {
        "ANTIBOT_HMAC_SECRET": {
            "en": "Antibot secret",
            "fr": "Secret antibot",
            "de": "Antibot-Geheimnis",
            "es": "Secreto antibot",
        },
    }


def load_schema_block_03_labels_31():
    return {
        "POSTGRES_WEB_PASSWORD": {
            "en": "Web database password",
            "fr": "Mot de passe de la base web",
            "de": "Passwort der Web-Datenbank",
            "es": "Contraseña de la base web",
        },
    }


def load_schema_block_03_labels_32():
    return {
        "TURNSTILE_SITE_KEY": {
            "en": "Turnstile site key",
            "fr": "Clé de site Turnstile",
            "de": "Turnstile-Site-Schlüssel",
            "es": "Clave de sitio Turnstile",
        },
    }


def load_schema_block_03_labels_33():
    return {
        "TURNSTILE_SECRET_KEY": {
            "en": "Turnstile secret key",
            "fr": "Clé secrète Turnstile",
            "de": "Turnstile-Geheimschlüssel",
            "es": "Clave secreta Turnstile",
        },
    }


def load_schema_block_03_labels_34():
    return {
        "UNBOUND_FORWARDERS": {
            "en": "DNS forwarders",
            "fr": "Relais DNS",
            "de": "DNS-Weiterleitungen",
            "es": "Reenviadores DNS",
        },
    }


def load_schema_block_03_labels_35():
    return {
        "USBGUARD_ENABLE": {
            "en": "Enable USBGuard",
            "fr": "Activer USBGuard",
            "de": "USBGuard aktivieren",
            "es": "Activar USBGuard",
        },
    }


def load_schema_block_03_labels_36():
    return {
        "DDOS_HARDENING_LEVEL": {
            "en": "DDoS hardening level",
            "fr": "Niveau de durcissement DDoS",
            "de": "DDoS-Härtungsstufe",
            "es": "Nivel de endurecimiento DDoS",
        },
    }


def load_schema_block_03_labels_37():
    return {
        "HOSTNAME_MATRIX": {
            "en": "Matrix hostname",
            "fr": "Nom d'hôte Matrix",
            "de": "Matrix-Hostname",
            "es": "Nombre de host Matrix",
        },
    }


def load_schema_block_03_labels_38():
    return {
        "HOSTNAME_LIVEKIT": {
            "en": "LiveKit hostname",
            "fr": "Nom d'hôte LiveKit",
            "de": "LiveKit-Hostname",
            "es": "Nombre de host LiveKit",
        },
    }


def load_schema_block_03_labels_39():
    return {
        "HOSTNAME_WIREGUARD": {
            "en": "WireGuard hostname",
            "fr": "Nom d'hôte WireGuard",
            "de": "WireGuard-Hostname",
            "es": "Nombre de host WireGuard",
        },
    }


def load_schema_block_03_labels_40():
    return {
        "SWAP_SIZE": {"en": "Swap size", "fr": "Taille du swap", "de": "Swap-Größe", "es": "Tamaño del swap"},
        "SWAP_FILE": {"en": "Swap file", "fr": "Fichier de swap", "de": "Swap-Datei", "es": "Archivo de swap"},
        "SWAP_MAPPER_NAME": {
            "en": "Swap mapper name",
            "fr": "Nom du mappeur de swap",
            "de": "Name des Swap-Mappers",
            "es": "Nombre del mapeador de swap",
        },
    }


def load_schema_block_03_labels_41():
    return {
        "CRON_USER": {"en": "Cron account", "fr": "Compte cron", "de": "Cron-Konto", "es": "Cuenta cron"},
        "NGINX_ADMIN_USER": {
            "en": "Nginx admin account",
            "fr": "Compte admin Nginx",
            "de": "Nginx-Adminkonto",
            "es": "Cuenta de admin Nginx",
        },
    }


def load_schema_block_03_labels_42():
    return {
        "NGINX_HTPASSWD_PATH": {
            "en": "Nginx password file",
            "fr": "Fichier de mots de passe Nginx",
            "de": "Nginx-Passwortdatei",
            "es": "Archivo de contraseñas Nginx",
        },
    }


def load_schema_block_03_labels_43():
    return {
        "NGINX_HTPASSWD_REALM": {
            "en": "Nginx authentication realm",
            "fr": "Domaine d'authentification Nginx",
            "de": "Nginx-Authentifizierungsbereich",
            "es": "Reino de autenticación Nginx",
        },
    }


def load_schema_block_03_labels_44():
    return {
        "DOCKER_NETWORK_PRODUCTION": {
            "en": "Production Docker network",
            "fr": "Réseau Docker de production",
            "de": "Docker-Netz der Produktion",
            "es": "Red Docker de producción",
        },
    }


def load_schema_block_03_labels_45():
    return {
        "DOCKER_NETWORK_SECURITY": {
            "en": "Security Docker network",
            "fr": "Réseau Docker de sécurité",
            "de": "Docker-Netz der Sicherheit",
            "es": "Red Docker de seguridad",
        },
    }


def load_schema_block_03_labels_46():
    return {
        "DOCKER_LOG_DRIVER": {
            "en": "Docker log driver",
            "fr": "Pilote de journaux Docker",
            "de": "Docker-Protokolltreiber",
            "es": "Controlador de registros Docker",
        },
    }


def load_schema_block_03_labels_47():
    return {
        "DOCKER_LOG_MAX_SIZE": {
            "en": "Docker log file size",
            "fr": "Taille d'un journal Docker",
            "de": "Größe einer Docker-Protokolldatei",
            "es": "Tamaño de un registro Docker",
        },
    }


def load_schema_block_03_labels_48():
    return {
        "DOCKER_LOG_MAX_FILE": {
            "en": "Docker log file count",
            "fr": "Nombre de journaux Docker",
            "de": "Anzahl der Docker-Protokolldateien",
            "es": "Número de registros Docker",
        },
    }


def load_schema_block_03_labels_49():
    return {
        "DOCKER_LOG_COMPRESS": {
            "en": "Compress Docker logs",
            "fr": "Compresser les journaux Docker",
            "de": "Docker-Protokolle komprimieren",
            "es": "Comprimir los registros Docker",
        },
    }


def load_schema_block_03_labels_50():
    return {
        "POSTGRES_SYNAPSE_USER": {
            "en": "Synapse database account",
            "fr": "Compte de la base Synapse",
            "de": "Konto der Synapse-Datenbank",
            "es": "Cuenta de la base Synapse",
        },
    }


def load_schema_block_03_labels_51():
    return {
        "POSTGRES_SYNAPSE_DB": {
            "en": "Synapse database name",
            "fr": "Nom de la base Synapse",
            "de": "Name der Synapse-Datenbank",
            "es": "Nombre de la base Synapse",
        },
    }


def load_schema_block_03_labels_52():
    return {
        "POSTGRES_KEYCLOAK_USER": {
            "en": "Keycloak database account",
            "fr": "Compte de la base Keycloak",
            "de": "Konto der Keycloak-Datenbank",
            "es": "Cuenta de la base Keycloak",
        },
    }


def load_schema_block_03_labels_53():
    return {
        "POSTGRES_KEYCLOAK_DB": {
            "en": "Keycloak database name",
            "fr": "Nom de la base Keycloak",
            "de": "Name der Keycloak-Datenbank",
            "es": "Nombre de la base Keycloak",
        },
    }


def load_schema_block_03_labels_54():
    return {
        "POSTGRES_WEB_USER": {
            "en": "Web database account",
            "fr": "Compte de la base web",
            "de": "Konto der Web-Datenbank",
            "es": "Cuenta de la base web",
        },
    }


def load_schema_block_03_labels_55():
    return {
        "POSTGRES_WEB_DB": {
            "en": "Web database name",
            "fr": "Nom de la base web",
            "de": "Name der Web-Datenbank",
            "es": "Nombre de la base web",
        },
    }


def load_schema_block_03_labels_56():
    return {
        "PORT_CROWDSEC_LAPI": {
            "en": "CrowdSec LAPI port",
            "fr": "Port LAPI CrowdSec",
            "de": "CrowdSec-LAPI-Port",
            "es": "Puerto LAPI de CrowdSec",
        },
    }


def load_schema_block_03_labels_57():
    return {
        "PORT_SYNAPSE_POSTGRESQL": {
            "en": "Synapse PostgreSQL port",
            "fr": "Port PostgreSQL de Synapse",
            "de": "Synapse-PostgreSQL-Port",
            "es": "Puerto PostgreSQL de Synapse",
        },
    }


def load_schema_block_03_labels_58():
    return {
        "PORT_SYNAPSE": {"en": "Synapse port", "fr": "Port Synapse", "de": "Synapse-Port", "es": "Puerto Synapse"},
        "PORT_ELEMENT": {"en": "Element port", "fr": "Port Element", "de": "Element-Port", "es": "Puerto Element"},
        "PORT_WEB_UI": {
            "en": "Web interface port",
            "fr": "Port de l'interface web",
            "de": "Port der Weboberfläche",
            "es": "Puerto de la interfaz web",
        },
    }


def load_schema_block_03_labels_59():
    return {
        "PORT_WEB_API": {
            "en": "Web API port",
            "fr": "Port de l'API web",
            "de": "Port der Web-API",
            "es": "Puerto de la API web",
        },
    }


def load_schema_block_03_labels_60():
    return {
        "PORT_SYNAPSE_ADMIN": {
            "en": "Synapse admin port",
            "fr": "Port d'admin Synapse",
            "de": "Synapse-Admin-Port",
            "es": "Puerto de admin Synapse",
        },
    }


def load_schema_block_03_labels_61():
    return {
        "PORT_PROMETHEUS": {
            "en": "Prometheus port",
            "fr": "Port Prometheus",
            "de": "Prometheus-Port",
            "es": "Puerto Prometheus",
        },
    }


def load_schema_block_03_labels_62():
    return {
        "PORT_KEYCLOAK": {"en": "Keycloak port", "fr": "Port Keycloak", "de": "Keycloak-Port", "es": "Puerto Keycloak"},
        "PORT_LIVEKIT_SFU": {
            "en": "LiveKit SFU port",
            "fr": "Port SFU LiveKit",
            "de": "LiveKit-SFU-Port",
            "es": "Puerto SFU de LiveKit",
        },
    }


def load_schema_block_03_labels_63():
    return {
        "PORT_LIVEKIT_JWT": {
            "en": "LiveKit JWT port",
            "fr": "Port JWT LiveKit",
            "de": "LiveKit-JWT-Port",
            "es": "Puerto JWT de LiveKit",
        },
    }


def load_schema_block_03_labels_64():
    return {
        "PORT_LIVEKIT_REDIS": {
            "en": "LiveKit Redis port",
            "fr": "Port Redis LiveKit",
            "de": "LiveKit-Redis-Port",
            "es": "Puerto Redis de LiveKit",
        },
    }


def load_schema_block_03_labels_65():
    return {
        "PORT_WIREGUARD_UI": {
            "en": "WireGuard interface port",
            "fr": "Port de l'interface WireGuard",
            "de": "WireGuard-Oberflächenport",
            "es": "Puerto de la interfaz WireGuard",
        },
    }


def load_schema_block_03_labels_66():
    return {
        "PORT_WIREGUARD_UDP": {
            "en": "WireGuard UDP port",
            "fr": "Port UDP WireGuard",
            "de": "WireGuard-UDP-Port",
            "es": "Puerto UDP de WireGuard",
        },
    }


def load_schema_block_03_labels_67():
    return {
        "WEB_REGISTRY": {
            "en": "Container registry",
            "fr": "Registre d'images",
            "de": "Container-Registry",
            "es": "Registro de imágenes",
        },
    }


def load_schema_block_03_labels_68():
    return {
        "WEB_IMAGE_FRONTEND": {
            "en": "Frontend image",
            "fr": "Image du frontend",
            "de": "Frontend-Image",
            "es": "Imagen del frontend",
        },
    }


def load_schema_block_03_labels_69():
    return {
        "WEB_IMAGE_BACKEND": {
            "en": "Backend image",
            "fr": "Image du backend",
            "de": "Backend-Image",
            "es": "Imagen del backend",
        },
    }


def load_schema_block_03_labels_70():
    return {
        "WEB_IMAGE_TAG": {"en": "Image tag", "fr": "Étiquette d'image", "de": "Image-Tag", "es": "Etiqueta de imagen"},
        "WEB_UPDATE_SCRIPT": {
            "en": "Update script",
            "fr": "Script de mise à jour",
            "de": "Aktualisierungsskript",
            "es": "Script de actualización",
        },
    }


def load_schema_block_03_labels_71():
    return {
        "MATRIX_ADMIN_USER": {
            "en": "Matrix admin account",
            "fr": "Compte admin Matrix",
            "de": "Matrix-Adminkonto",
            "es": "Cuenta de admin Matrix",
        },
    }


def load_schema_block_03_labels_72():
    return {
        "KEYCLOAK_REALM": {
            "en": "Keycloak realm",
            "fr": "Royaume Keycloak",
            "de": "Keycloak-Realm",
            "es": "Reino Keycloak",
        },
    }


def load_schema_block_03_labels_73():
    return {
        "KEYCLOAK_CLIENT": {
            "en": "Keycloak client",
            "fr": "Client Keycloak",
            "de": "Keycloak-Client",
            "es": "Cliente Keycloak",
        },
    }


def load_schema_block_03_labels_74():
    return {
        "KC_BOOTSTRAP_ADMIN_USERNAME": {
            "en": "Keycloak bootstrap admin",
            "fr": "Admin initial Keycloak",
            "de": "Keycloak-Startadmin",
            "es": "Admin inicial de Keycloak",
        },
    }


def load_schema_block_03_labels_75():
    return {
        "WIREGUARD_DEFAULT_DNS": {
            "en": "WireGuard DNS",
            "fr": "DNS WireGuard",
            "de": "WireGuard-DNS",
            "es": "DNS de WireGuard",
        },
    }


def load_schema_block_03_labels_76():
    return {
        "WIREGUARD_DEFAULT_ADDRESS": {
            "en": "WireGuard address",
            "fr": "Adresse WireGuard",
            "de": "WireGuard-Adresse",
            "es": "Dirección WireGuard",
        },
    }


def load_schema_block_03_labels_77():
    return {
        "WIREGUARD_ALLOWED_IP": {
            "en": "WireGuard allowed addresses",
            "fr": "Adresses autorisées WireGuard",
            "de": "Erlaubte WireGuard-Adressen",
            "es": "Direcciones permitidas de WireGuard",
        },
    }


def load_schema_block_03_labels_join_01():
    found = {}
    found.update(load_schema_block_03_labels_01())
    found.update(load_schema_block_03_labels_02())
    found.update(load_schema_block_03_labels_03())
    found.update(load_schema_block_03_labels_04())
    found.update(load_schema_block_03_labels_05())
    found.update(load_schema_block_03_labels_06())
    found.update(load_schema_block_03_labels_07())
    found.update(load_schema_block_03_labels_08())
    found.update(load_schema_block_03_labels_09())
    found.update(load_schema_block_03_labels_10())
    found.update(load_schema_block_03_labels_11())
    found.update(load_schema_block_03_labels_12())
    found.update(load_schema_block_03_labels_13())
    found.update(load_schema_block_03_labels_14())
    found.update(load_schema_block_03_labels_15())
    found.update(load_schema_block_03_labels_16())
    found.update(load_schema_block_03_labels_17())
    found.update(load_schema_block_03_labels_18())
    found.update(load_schema_block_03_labels_19())
    found.update(load_schema_block_03_labels_20())
    found.update(load_schema_block_03_labels_21())
    found.update(load_schema_block_03_labels_22())
    found.update(load_schema_block_03_labels_23())
    found.update(load_schema_block_03_labels_24())
    found.update(load_schema_block_03_labels_25())
    found.update(load_schema_block_03_labels_26())
    found.update(load_schema_block_03_labels_27())
    found.update(load_schema_block_03_labels_28())
    found.update(load_schema_block_03_labels_29())
    found.update(load_schema_block_03_labels_30())
    return found


def load_schema_block_03_labels_join_02():
    found = {}
    found.update(load_schema_block_03_labels_31())
    found.update(load_schema_block_03_labels_32())
    found.update(load_schema_block_03_labels_33())
    found.update(load_schema_block_03_labels_34())
    found.update(load_schema_block_03_labels_35())
    found.update(load_schema_block_03_labels_36())
    found.update(load_schema_block_03_labels_37())
    found.update(load_schema_block_03_labels_38())
    found.update(load_schema_block_03_labels_39())
    found.update(load_schema_block_03_labels_40())
    found.update(load_schema_block_03_labels_41())
    found.update(load_schema_block_03_labels_42())
    found.update(load_schema_block_03_labels_43())
    found.update(load_schema_block_03_labels_44())
    found.update(load_schema_block_03_labels_45())
    found.update(load_schema_block_03_labels_46())
    found.update(load_schema_block_03_labels_47())
    found.update(load_schema_block_03_labels_48())
    found.update(load_schema_block_03_labels_49())
    found.update(load_schema_block_03_labels_50())
    found.update(load_schema_block_03_labels_51())
    found.update(load_schema_block_03_labels_52())
    found.update(load_schema_block_03_labels_53())
    found.update(load_schema_block_03_labels_54())
    found.update(load_schema_block_03_labels_55())
    found.update(load_schema_block_03_labels_56())
    found.update(load_schema_block_03_labels_57())
    found.update(load_schema_block_03_labels_58())
    found.update(load_schema_block_03_labels_59())
    found.update(load_schema_block_03_labels_60())
    return found


def load_schema_block_03_labels_join_03():
    found = {}
    found.update(load_schema_block_03_labels_61())
    found.update(load_schema_block_03_labels_62())
    found.update(load_schema_block_03_labels_63())
    found.update(load_schema_block_03_labels_64())
    found.update(load_schema_block_03_labels_65())
    found.update(load_schema_block_03_labels_66())
    found.update(load_schema_block_03_labels_67())
    found.update(load_schema_block_03_labels_68())
    found.update(load_schema_block_03_labels_69())
    found.update(load_schema_block_03_labels_70())
    found.update(load_schema_block_03_labels_71())
    found.update(load_schema_block_03_labels_72())
    found.update(load_schema_block_03_labels_73())
    found.update(load_schema_block_03_labels_74())
    found.update(load_schema_block_03_labels_75())
    found.update(load_schema_block_03_labels_76())
    found.update(load_schema_block_03_labels_77())
    return found


def load_schema_block_03_labels():
    global labels
    labels = {}
    labels.update(load_schema_block_03_labels_join_01())
    labels.update(load_schema_block_03_labels_join_02())
    labels.update(load_schema_block_03_labels_join_03())


def load_schema_block_03_01():
    global allowed
    allowed = {
        "workstation": ["INSTALL_DIRECTORY", "PROJECT_SLUG", "CONFIG_BASE_DIRECTORY"],
        "server": [
            "DOMAIN",
            "CONFIG_BASE_DIRECTORY",
            "DOCKER_BASE_DIRECTORY",
            "SECRET_DIRECTORY",
            "DOMAIN_SYNAPSE",
            "DOMAIN_ELEMENT",
            "DOMAIN_KEYCLOAK",
            "MAIN_GROUP",
            "INSTALL_DIRECTORY",
        ],
    }
    # One clear label per listed variable, in every language. The key is LABEL_<NAME>.


def load_schema_block_03():
    load_schema_block_03_01()
    load_schema_block_03_labels()


load_schema_block_03()


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


def label_names_of(listed):
    used = set()
    for names in listed.values():
        used.update(names)
    return used


def require_label_set(used):
    missing_labels = sorted(used - set(labels))
    unused_labels = sorted(set(labels) - used)
    if missing_labels:
        die("label missing " + " ".join(missing_labels))
    if unused_labels:
        die("label unused " + " ".join(unused_labels))


def bad_label_text(text):
    if not text:
        return True
    if "\n" in text:
        return True
    return text.startswith("[")


def require_label_text():
    for name, texts in labels.items():
        if set(texts) != {"en", "fr", "de", "es"}:
            die(f"label languages {name}")
        for lang, text in texts.items():
            if bad_label_text(text):
                die(f"label text {name} {lang}")


def require_labels():
    listed = {product: listed_names(product) for product in products}
    require_label_set(label_names_of(listed))
    require_label_text()
    return listed


def read_product(product):
    parsed = []
    for filename in conf_names:
        path = root / product / "config" / filename
        parsed.extend(parse_conf(path, filename))
    return parsed


def require_assignments(product, parsed):
    seen = [item["name"] for item in parsed]
    if len(seen) != len(set(seen)):
        die(f"duplicate assignment {product}")
    known = set(rules[product])
    if set(seen) != known:
        missing = sorted(set(seen) - known)
        extra = sorted(known - set(seen))
        die(f"rule mismatch {product} missing={missing} extra={extra}")


def require_secret_defaults(variables):
    for variable in variables:
        if variable["file"] == "secrets.conf" and "default" in variable:
            die(f"secret default refused {variable['name']}")


def schema_text(product, variables):
    document = {
        "product": product,
        "pattern_engine": "bash",
        "allowed_references": allowed[product],
        "empty_default_references": ["INSTALL_DIRECTORY"],
        "forbidden": ["`", "$("],
        "files": [file_record(filename) for filename in conf_names],
        "variables": variables,
    }
    return json.dumps(document, indent=2, ensure_ascii=False) + "\n"


def list_rows(product, variables, list_mode):
    by_name = {item["name"]: item for item in variables}
    rows = []
    for lot, names in lots[product]:
        for name in names:
            item = by_name[name]
            if list_mode == "basic" and item["file"] == "global.conf":
                continue
            rows.append((lot, item["file"], name))
    return rows


def list_text(rows):
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(("lot", "file", "name"))
    writer.writerows(rows)
    return buffer.getvalue()


def product_documents(product):
    parsed = read_product(product)
    require_assignments(product, parsed)
    variables = [publish(product, item) for item in parsed]
    require_secret_defaults(variables)
    found = {}
    schema = "configuration.json"
    found[f"{product}/config/schema/{schema}"] = schema_text(product, variables)
    for list_mode in ("basic", "advanced"):
        rows = list_rows(product, variables, list_mode)
        found[f"config-{product}-{list_mode}.csv"] = list_text(rows)
    return found


def locale_names(listed):
    label_names = []
    seen_labels = set()
    for product in products:
        for name in listed[product]:
            if name in seen_labels:
                continue
            seen_labels.add(name)
            label_names.append(name)
    return label_names


def locale_documents(listed):
    found = {}
    names = locale_names(listed)
    for lang in ("en", "fr", "de", "es"):
        blocks = [f"[LABEL_{name}]\n{labels[name][lang]}" for name in names]
        found[f"share/locale/{lang}/label.txt"] = "\n\n".join(blocks) + "\n"
    return found


def build_documents(listed):
    found = {}
    for product in products:
        found.update(product_documents(product))
    found.update(locale_documents(listed))
    return found


def report_stale(documents):
    stale = []
    for rel, text in documents.items():
        path = root / rel
        current = path.read_text(encoding="utf-8") if path.is_file() else None
        if current != text:
            stale.append(rel)
    if stale:
        die("stale " + " ".join(stale))


def emit_documents(documents):
    for rel, text in documents.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")


def run_config_list():
    listed = require_labels()
    documents = build_documents(listed)
    if mode == "check":
        report_stale(documents)
        return
    emit_documents(documents)


if __name__ == "__main__":
    run_config_list()
