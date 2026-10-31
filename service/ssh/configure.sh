#!/usr/bin/env bash
# =============================================================================
# File       : service/ssh/configure.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY
G_INSTALL_DIRECTORY="${INSTALL_DIRECTORY}"
export G_INSTALL_DIRECTORY

# shellcheck disable=SC2155
readonly DIR_SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${G_INSTALL_DIRECTORY}/core/lib.sh"
source "${G_INSTALL_DIRECTORY}/config/global.conf"

require_root
get_ssh_port

log_subtitle     "${INSTALL_WATCHER}" "configure.configuration-ssh-drop-in"
log_info         "${INSTALL_WATCHER}" "configure.port-detected" "${SSH_PORT}"
log_info         "${INSTALL_WATCHER}" "configure.configuration-of-ssh"
copy_backup /etc/ssh/sshd_config

ensure_directory /etc/ssh/sshd_config.d 755

install -m 644 "$(locate_config_file ssh/00-liltress-workstation.conf)" /etc/ssh/sshd_config.d/00-liltress-workstation.conf
rm -f /etc/ssh/sshd_config.d/99-liltress-workstation.conf

if [[ -f /etc/ssh/sshd_config ]]; then
    awk '
        /^[[:space:]]*Include[[:space:]]/ && !seen { seen = 1 }
        !seen && /^[[:space:]]*PermitRootLogin[[:space:]]/ {
            print "# Liltress Workstation : une définition plus bas impose PermitRootLogin no"
            print "# " $0
            next
        }
        { print }
    ' /etc/ssh/sshd_config > /etc/ssh/sshd_config.hfu \
        && cat /etc/ssh/sshd_config.hfu > /etc/ssh/sshd_config \
        && rm -f /etc/ssh/sshd_config.hfu

    if ! grep -q 'Liltress Workstation permit-root' /etc/ssh/sshd_config \
        && ! grep -q 'High-Fortress User permit-root' /etc/ssh/sshd_config; then
        cat "$(locate_config_file ssh/permit-root.conf)" >> /etc/ssh/sshd_config
    fi
fi
for snippet in /etc/ssh/sshd_config.d/*.conf; do
    [[ -f "${snippet}" ]] || continue
    [[ "${snippet}" == *00-liltress-workstation.conf ]] && continue
    if grep -qE '^[[:space:]]*PermitRootLogin[[:space:]]' "${snippet}"; then
        sed -i 's/^[[:space:]]*PermitRootLogin[[:space:]].*/# Liltress Workstation : le drop-in 00- pose PermitRootLogin no\n# &/' "${snippet}"
    fi
done

ensure_directory "$(dirname "${G_SSH_BANNER_PATH}")" 755
ensure_directory /run/sshd 755
printf '%s\n' "${G_BANNER_MESSAGE}" > "${G_SSH_BANNER_PATH}"
chmod 644 "${G_SSH_BANNER_PATH}"

log_info         "${INSTALL_WATCHER}" "configure.ssh.info.3"
if ! sshd -t; then
    log_error        "${INSTALL_WATCHER}" "configure.sshd-t-a-failed-drop-in-removed"
fi
root_login="$(get_sshd_value permitrootlogin)"
if [[ "${root_login}" != "no" ]]; then
    log_error        "${INSTALL_WATCHER}" "configure.effective-permitrootlogin-expected-no" "${root_login:-inconnu}"
fi

log_info         "${INSTALL_WATCHER}" "configure.pass-of-ssh-in-service-not-only-the-activation-b"
run_optional     "${INSTALL_WATCHER}" "configure.ssh.error.3" systemctl disable --now ssh.socket
run_optional     "${INSTALL_WATCHER}" "configure.ssh.error.4" systemctl unmask "${G_SSH_SERVICE_NAME}.service"
run_silent       "${INSTALL_WATCHER}" "configure.ssh.error.5" systemctl enable --now "${G_SSH_SERVICE_NAME}.service"
run_silent       "${INSTALL_WATCHER}" "configure.ssh.error.6" systemctl reload-or-restart "${G_SSH_SERVICE_NAME}"
log_success      "${INSTALL_WATCHER}" "configure.hardened-ssh-root-forbidden-password-kept-port" "${SSH_PORT}"
