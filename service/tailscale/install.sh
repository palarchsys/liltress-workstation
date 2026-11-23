#!/usr/bin/env bash
# =============================================================================
# File       : service/tailscale/install.sh
# Updated at : 2026-11-23
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Install Tailscale from the signed apt repository.
# Note       : The daemon starts here. The login happens in configure.sh.
# -----------------------------------------------------------------------------


INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"

read_os_codename() {
    local codename=""
    codename="$(sed -n 's/^VERSION_CODENAME=//p' /etc/os-release)"
    codename="${codename%\"}"
    codename="${codename#\"}"
    printf '%s\n' "${codename}"
}

check_tailscale_suite() {
    local suite="$1"
    local code
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
        "https://pkgs.tailscale.com/stable/ubuntu/${suite}.tailscale-keyring.list" || true)"
    [[ "${code}" == "200" ]]
}

locate_tailscale_suite() {
    local host suite
    host="$(read_os_codename)"
    if check_tailscale_suite "${host}"; then
        printf '%s\n' "${host}"
        return 0
    fi
    for suite in resolute questing plucky oracular noble jammy; do
        [[ "${suite}" == "${host}" ]] && continue
        if check_tailscale_suite "${suite}"; then
            printf '%s\n' "${suite}"
            return 0
        fi
    done
    return 1
}

add_tailscale_source() {
    local suite="$1"
    local key="/usr/share/keyrings/tailscale-archive-keyring.gpg"
    install -d -m 755 /usr/share/keyrings /etc/apt/sources.list.d
    curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${suite}.noarmor.gpg" -o "${key}"
    curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${suite}.tailscale-keyring.list" \
        -o /etc/apt/sources.list.d/tailscale.list
    chmod 644 "${key}" /etc/apt/sources.list.d/tailscale.list
}

install_tailscale_package() {
    local suite
    suite="$(locate_tailscale_suite)" || log_error "${INSTALL_WATCHER}" "install.tailscale.missing"
    log_info "${INSTALL_WATCHER}" "install.tailscale.start"
    log_info "${INSTALL_WATCHER}" "install.tailscale.suite" "${suite}"
    add_tailscale_source "${suite}"
    run_silent_apt "${INSTALL_WATCHER}" "update" "install.tailscale.missing"
    run_silent_apt "${INSTALL_WATCHER}" "install -y tailscale" "install.tailscale.missing"
    systemctl enable --now tailscaled
    log_success "${INSTALL_WATCHER}" "install.tailscale.ready"
}
require_root

install_tailscale_package
