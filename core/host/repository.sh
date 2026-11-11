#!/usr/bin/env bash
# =============================================================================
# File       : core/host/repository.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================


check_repository_key() {
    local path="$1"
    [[ -n "${path}" && -s "${path}" ]] || return 1
    gpg --batch --quiet --show-keys -- "${path}" >/dev/null 2>&1
}

install_repository_key() {
    local url="$1"
    local dest="$2"
    local body="" key_tmp="" err_file="" curl_err="" dest_dir="" staged=""
    dest_dir="$(dirname -- "${dest}")"
    if [[ ! -d "${dest_dir}" ]]; then
        log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error" "${dest}"
    fi
    body="$(mktemp)"
    key_tmp="$(mktemp)"
    err_file="$(mktemp)"
    if ! curl -fsSL -o "${body}" -- "${url}" 2>"${err_file}"; then
        curl_err="$(tr '\n' ' ' < "${err_file}" || true)"
        rm -f -- "${body}" "${key_tmp}" "${err_file}"
        if [[ "${curl_err}" == *[Nn]ot\ yet\ valid* || "${curl_err}" == *clock\ is\ incorrect* ]]; then
            log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.2" "${dest}"
        fi
        log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error" "${dest}"
    fi
    if ! gpg --batch --yes --dearmor -o "${key_tmp}" -- "${body}" 2>"${err_file}"; then
        rm -f -- "${body}" "${key_tmp}" "${err_file}"
        log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.4" "${dest}"
    fi
    if ! check_repository_key "${key_tmp}"; then
        rm -f -- "${body}" "${key_tmp}" "${err_file}"
        log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.5" "${dest}"
    fi
    staged="$(mktemp "${dest_dir}/key.XXXXXX")"
    cp -f -- "${key_tmp}" "${staged}"
    chmod 644 "${staged}"
    if [[ "$(id -u)" -eq 0 ]]; then
        chown root:root -- "${staged}"
    fi
    mv -f -- "${staged}" "${dest}"
    rm -f -- "${body}" "${key_tmp}" "${err_file}"
}
