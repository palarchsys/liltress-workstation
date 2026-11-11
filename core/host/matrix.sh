#!/usr/bin/env bash
# =============================================================================
# File       : core/host/matrix.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================


check_localhost_port() {
    local port="$1"
    local line
    line="$(ss -ltnp "sport = :${port}" 2>/dev/null | awk 'NR>1')"
    if [[ -n "${line}" ]]; then
        log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.6" "${port}" "${port}" "${line}"
    fi
}

set_main_hostname() {
    case "${SERVER_TYPE:-}" in
        MATRIX)    MAIN_HOSTNAME="${HOSTNAME_MATRIX}" ;;
        LIVEKIT)   MAIN_HOSTNAME="${HOSTNAME_LIVEKIT}" ;;
        WIREGUARD) MAIN_HOSTNAME="${HOSTNAME_WIREGUARD}" ;;
        *) log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.7" "${SERVER_TYPE:-}";;
    esac
    export MAIN_HOSTNAME
}

get_matrix_admin_token() {
    local url="${MATRIX_URL:-http://127.0.0.1:8008}"
    local user="${MATRIX_ADMIN_USER}"
    local pass="${MATRIX_ADMIN_PASSWORD}"

    if [ -z "$user" ] || [ -z "$pass" ]; then
        log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.8"
    fi

    log_info "${INSTALL_WATCHER:-BASH}" "install.lib.info" "${user}"

    local payload
    payload=$(jq -n --arg user "$user" --arg pass "$pass" \
        '{type: "m.login.password", user: $user, password: $pass}')

    local response
    response=$(curl -s -X POST "${url}/_matrix/client/v3/login" \
        -H "Content-Type: application/json" \
        -d "${payload}")

    MATRIX_ADMIN_ACCESS_TOKEN=$(echo "$response" | jq -r '.access_token // empty')

    if [ -z "$MATRIX_ADMIN_ACCESS_TOKEN" ]; then
        log_info "${INSTALL_WATCHER:-BASH}" "install.lib.info.2" "${response}"
        printf '%s\n' "${response}" | jq . 2>/dev/null || printf '%s\n' "${response}"
        log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.9"
    fi

    log_success "${INSTALL_WATCHER:-BASH}" "install.lib.success"
}
