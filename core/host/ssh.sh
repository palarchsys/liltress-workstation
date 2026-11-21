#!/usr/bin/env bash
# =============================================================================
# File       : core/host/ssh.sh
# Updated at : 2026-11-21
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Resolve the effective daemon setting and write the drop-in.
# -----------------------------------------------------------------------------


# The first matching keyword from standard input is printed in lowercase.
read_sshd_value() {
    local keyword="${1,,}"
    awk -v key="${keyword}" 'tolower($1) == key { print tolower($2); exit }'
}

# Print one effective sshd setting. 10.2 uses lowercase, 10.5 uses canonical case.

get_sshd_value() {
    local keyword="${1,,}"
    sshd -T 2>/dev/null | read_sshd_value "${keyword}"
}

install_sshd_dropin() {
    local account="$1"
    local stem="$2"
    local src dest
    src="$(locate_config_file "ssh/00-${stem}.conf")"
    dest="/etc/ssh/sshd_config.d/00-${stem}.conf"
    ensure_directory /etc/ssh/sshd_config.d 755
    SSH_ACCOUNT="${account}" \
        SSH_PORT="${SSH_PORT}" \
        SSH_BANNER_PATH="${SSH_BANNER_PATH}" \
        SSH_MAX_AUTH_TRIES="${SSH_MAX_AUTH_TRIES}" \
        SSH_CLIENT_ALIVE_INTERVAL="${SSH_CLIENT_ALIVE_INTERVAL}" \
        SSH_CLIENT_ALIVE_COUNT_MAX="${SSH_CLIENT_ALIVE_COUNT_MAX}" \
        SSH_LOGIN_GRACE_TIME="${SSH_LOGIN_GRACE_TIME}" \
        SSH_TCP_KEEPALIVE="${SSH_TCP_KEEPALIVE}" \
        SSH_MAX_SESSIONS="${SSH_MAX_SESSIONS}" \
        envsubst '${SSH_PORT} ${SSH_ACCOUNT} ${SSH_BANNER_PATH} ${SSH_MAX_AUTH_TRIES} ${SSH_CLIENT_ALIVE_INTERVAL} ${SSH_CLIENT_ALIVE_COUNT_MAX} ${SSH_LOGIN_GRACE_TIME} ${SSH_TCP_KEEPALIVE} ${SSH_MAX_SESSIONS}' <"${src}" >"${dest}"
    install -m 644 "$(locate_config_file "ssh/99-${stem}.conf")" "/etc/ssh/sshd_config.d/99-${stem}.conf"
    chmod 644 "${dest}"
}

reload_sshd_unit() {
    systemctl enable "${SSH_SERVICE_NAME}.service" >/dev/null 2>&1 || true
    if systemctl is-active --quiet "${SSH_SERVICE_NAME}.service"; then
        systemctl reload "${SSH_SERVICE_NAME}.service"
        return 0
    fi
    systemctl start "${SSH_SERVICE_NAME}.service"
}

get_ssh_port() {
    local port="22"
    if command -v sshd >/dev/null 2>&1; then
        port="$(get_sshd_value port)"
        [[ -z "$port" ]] && port="22"
    fi
    SSH_PORT="$port"
    export SSH_PORT
}
