#!/usr/bin/env bash
# =============================================================================
# File       : core/host/runtime.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================


set_statoverride_user_exec() {
    local path="$1"
    local out=""
    [[ -e "${path}" && ! -L "${path}" ]] || return 0
    if dpkg-statoverride --list "${path}" >/dev/null 2>&1; then
        out="$(dpkg-statoverride --remove "${path}" 2>&1)" || log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.10" "${path}" "${out}"
    fi
    out="$(dpkg-statoverride --update --add "${MAIN_USER}" "${MAIN_GROUP}" 500 "${path}" 2>&1)" \
        || log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.11" "${path}" "${out}"
}

lock_npm_to_main_user() {
    [[ "${SERVER_TYPE:-}" == "MATRIX" ]] || return 0
    command -v dpkg-statoverride >/dev/null 2>&1 || return 0
    local have_npm=0 have_corepack=0
    dpkg -s npm >/dev/null 2>&1 && have_npm=1
    dpkg -s node-corepack >/dev/null 2>&1 && have_corepack=1
    [[ "${have_npm}" -eq 1 || "${have_corepack}" -eq 1 ]] || return 0
    [[ -n "${MAIN_USER:-}" && -n "${MAIN_GROUP:-}" ]] || log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.12"
    getent passwd "${MAIN_USER}" >/dev/null || log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.13" "${MAIN_USER}"
    getent group "${MAIN_GROUP}" >/dev/null || log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.14" "${MAIN_GROUP}"
    log_info "${INSTALL_WATCHER:-BASH}" "install.lib.info.3" "${MAIN_USER}"

    local listed="" real="" root="" locked=0
    while IFS= read -r listed; do
        [[ -n "${listed}" ]] || continue
        case "${listed}" in
            /usr/share/doc/*|/usr/share/man/*|/usr/share/lintian/*) continue ;;
            /usr/bin/node|/usr/bin/nodejs) continue ;;
        esac
        if [[ "${listed}" == /usr/bin/* || "${listed}" == /usr/local/bin/* ]]; then
            if [[ -L "${listed}" ]]; then
                real="$(readlink -f "${listed}" 2>/dev/null || true)"
                case "${real}" in
                    */bin/node|*/bin/nodejs|"") ;;
                    *)
                        if [[ -f "${real}" ]]; then
                            set_statoverride_user_exec "${real}"
                            locked=1
                        fi
                        ;;
                esac
            elif [[ -f "${listed}" ]]; then
                set_statoverride_user_exec "${listed}"
                locked=1
            fi
        fi
        if [[ "${listed}" == */npm-cli.js || "${listed}" == */npx-cli.js ]]; then
            real="$(dirname "${listed}")"
            if [[ "$(basename "${real}")" == "bin" ]]; then
                real="$(dirname "${real}")"
            fi
            if [[ -z "${root}" && -d "${real}" ]]; then
                root="${real}"
            fi
        fi
    done < <(if [[ "${have_npm}" -eq 1 ]]; then dpkg -L npm 2>/dev/null || true; fi)

    if [[ -n "${root}" ]]; then
        set_statoverride_user_exec "${root}"
        locked=1
    fi

    if [[ "${have_corepack}" -eq 1 && -d /usr/share/nodejs/corepack ]]; then
        set_statoverride_user_exec /usr/share/nodejs/corepack
        locked=1
    fi
    if [[ -e /usr/bin/corepack || -L /usr/bin/corepack ]]; then
        if [[ -L /usr/bin/corepack ]]; then
            real="$(readlink -f /usr/bin/corepack 2>/dev/null || true)"
        else
            real="/usr/bin/corepack"
        fi
        case "${real}" in
            */bin/node|*/bin/nodejs|"") ;;
            *)
                if [[ -n "${real}" && -f "${real}" ]]; then
                    set_statoverride_user_exec "${real}"
                    locked=1
                fi
                ;;
        esac
    fi
    if [[ "${have_npm}" -eq 1 && "${locked}" -eq 0 ]]; then
        log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.15" "${MAIN_USER}"
    fi
    [[ "${locked}" -eq 1 ]] || return 0
    log_success "${INSTALL_WATCHER:-BASH}" "install.lib.success.2" "${MAIN_USER}"
}

get_local_browser() {
    [[ "${MODE_TEST:-0}" == "1" || "${MODE_DEV:-0}" == "1" ]]
}

apply_runtime_urls() {
    if get_local_browser; then
        KEYCLOAK_PUBLIC_BASE_URL="http://127.0.0.1:${PORT_KEYCLOAK}"
        MATRIX_PUBLIC_BASE_URL="http://127.0.0.1:${PORT_SYNAPSE}"
        ELEMENT_PUBLIC_BASE_URL="http://127.0.0.1:${PORT_ELEMENT}"
        PUBLIC_BASE_URL="http://127.0.0.1:${PORT_WEB_UI}"
        API_BASE_URL="http://127.0.0.1:${PORT_WEB_API}"
        CORS_ORIGINS="http://127.0.0.1:${PORT_WEB_UI}"
        LIVEKIT_URL="ws://127.0.0.1:${PORT_LIVEKIT_SFU}"
        JWT_URL="http://127.0.0.1:${PORT_LIVEKIT_JWT}"
        WIREGUARD_HOST="127.0.0.1"
        WIREGUARD_UI_URL="http://127.0.0.1:${PORT_WIREGUARD_UI}"
    else
        PUBLIC_BASE_URL="https://${DOMAIN}"
        API_BASE_URL="https://${DOMAIN_WEB_API}"
        CORS_ORIGINS="https://${DOMAIN}"
        LIVEKIT_URL="wss://${DOMAIN_LIVEKIT_SFU}"
        JWT_URL="https://${DOMAIN_LIVEKIT_JWT}"
        WIREGUARD_HOST="${DOMAIN_WIREGUARD}"
        WIREGUARD_UI_URL="https://${DOMAIN_WIREGUARD}"
    fi
    export KEYCLOAK_PUBLIC_BASE_URL MATRIX_PUBLIC_BASE_URL ELEMENT_PUBLIC_BASE_URL
    export PUBLIC_BASE_URL API_BASE_URL CORS_ORIGINS
    export LIVEKIT_URL JWT_URL WIREGUARD_HOST WIREGUARD_UI_URL
}

set_mode_test_turnstile() {
    [[ "${MODE_TEST:-0}" == "1" ]] || return 0
    TURNSTILE_SITE_KEY="1x00000000000000000000AA"
    TURNSTILE_SECRET_KEY="1x0000000000000000000000000000000AA"
    export TURNSTILE_SITE_KEY TURNSTILE_SECRET_KEY
}

strip_mode_test_host() {
    [[ -f /etc/hosts ]] || return 0
    grep -q '# BEGIN liltress MODE_TEST' /etc/hosts || return 0
    log_info "${INSTALL_WATCHER:-BASH}" "install.lib.info.4"
    local tmp
    tmp="$(mktemp)"
    awk '
        $0 == "# BEGIN liltress MODE_TEST" { skip = 1; next }
        $0 == "# END liltress MODE_TEST" { skip = 0; next }
        skip { next }
        { print }
    ' /etc/hosts > "${tmp}"
    cat "${tmp}" > /etc/hosts
    rm -f "${tmp}"
    log_success "${INSTALL_WATCHER:-BASH}" "install.lib.success.3"
}

apply_mode_test_local() {
    [[ "${MODE_TEST:-0}" == "1" ]] || return 0

    local live="/etc/letsencrypt/live/${DOMAIN}"
    log_info "${INSTALL_WATCHER:-BASH}" "install.lib.info.5"
    mkdir -p "${live}"
    openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
        -keyout "${live}/privkey.pem" \
        -out "${live}/fullchain.pem" \
        -subj "/CN=${DOMAIN}" >/dev/null 2>&1
    chmod 640 "${live}/privkey.pem"
    chmod 644 "${live}/fullchain.pem"

    strip_mode_test_host
    if [[ -f /usr/local/share/ca-certificates/liltress-mode-test.crt ]]; then
        log_info "${INSTALL_WATCHER:-BASH}" "install.lib.info.6"
        rm -f /usr/local/share/ca-certificates/liltress-mode-test.crt
        update-ca-certificates >/dev/null || true
        log_success "${INSTALL_WATCHER:-BASH}" "install.lib.success.4"
    fi
    log_success "${INSTALL_WATCHER:-BASH}" "install.lib.success.5"
}
