#!/usr/bin/env bash
# =============================================================================
# File       : service/crowdsec/configure.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY
G_INSTALL_DIRECTORY="${INSTALL_DIRECTORY}"
export G_INSTALL_DIRECTORY

source "${G_INSTALL_DIRECTORY}/core/lib.sh"
source "${G_INSTALL_DIRECTORY}/config/global.conf"
require_root

log_subtitle     "${INSTALL_WATCHER}" "configure.collections-crowdsec"
log_info         "${INSTALL_WATCHER}" "configure.installation-of-the-collections-crowdsec"
run_silent       "${INSTALL_WATCHER}" "configure.crowdsec.error" cscli hub update

mapfile -t collections < <(grep -vE '^[[:space:]]*(#|$)' "$(locate_config_file crowdsec/collections.list)")
run_silent       "${INSTALL_WATCHER}" "configure.crowdsec.error" cscli collections install --force "${collections[@]}"
log_success      "${INSTALL_WATCHER}" "configure.collections-linux-sshd-postfix-and-allowlist-ins"

log_info         "${INSTALL_WATCHER}" "configure.search-of-the-collections-optional"
while read -r name; do
    [[ -n "${name}" && "${name}" != \#* ]] || continue
    if cscli collections install --force "${name}" >/dev/null 2>&1; then
        log_info         "${INSTALL_WATCHER}" "configure.collection-present-1" "${name}"
    else
        log_warn         "${INSTALL_WATCHER}" "configure.collection-absent-of-the-hub" "${name}"
    fi
done < "$(locate_config_file crowdsec/optional.list)"
log_success      "${INSTALL_WATCHER}" "configure.optional-collections-processed"

log_subtitle     "${INSTALL_WATCHER}" "configure.duration-of-block"
log_info         "${INSTALL_WATCHER}" "configure.configuration-of-the-duration-of-block"
# shellcheck disable=SC1091
source "$(locate_config_file crowdsec/ban.conf)"
if [[ ! "${W_CROWDSEC_BAN_DURATION}" =~ ^[0-9]+[smhd]$ ]]; then
    log_error        "${INSTALL_WATCHER}" "configure.duration-of-block-invalid"
fi
grep -v '^#' "$(locate_config_file crowdsec/profiles.yaml)" \
    | sed "s/duration: .*/duration: ${W_CROWDSEC_BAN_DURATION}/" \
    > /etc/crowdsec/profiles.yaml
log_success      "${INSTALL_WATCHER}" "configure.block-installed" "${W_CROWDSEC_BAN_DURATION}"

log_subtitle     "${INSTALL_WATCHER}" "configure.journals-read-by-crowdsec"
log_info         "${INSTALL_WATCHER}" "configure.configuration-of-the-journals-read-by-crowdsec"
{
    grep -v '^#' "$(locate_config_file crowdsec/acquisition-journal.yaml)"
    if [[ -f /var/log/auth.log ]]; then
        grep -v '^#' "$(locate_config_file crowdsec/acquisition-auth.yaml)"
    fi
    if [[ -f /var/log/syslog ]]; then
        grep -v '^#' "$(locate_config_file crowdsec/acquisition-syslog.yaml)"
    fi
    if [[ -f /var/log/mail.log ]]; then
        grep -v '^#' "$(locate_config_file crowdsec/acquisition-mail.yaml)"
    fi
} > /etc/crowdsec/acquisitions.yaml
chmod 644 /etc/crowdsec/acquisitions.yaml
log_success      "${INSTALL_WATCHER}" "configure.journals-ssh-system-and-mail-configured"

log_subtitle     "${INSTALL_WATCHER}" "configure.bouncer-firewall"
log_info         "${INSTALL_WATCHER}" "configure.binding-of-the-bouncer-nftables-to-the-api-local"
cscli bouncers delete firewall-bouncer >/dev/null 2>&1 || true
raw="$(cscli bouncers add firewall-bouncer 2>&1)"
key="$(printf '%s\n' "${raw}" | grep -oE '[A-Za-z0-9/=+]{40,}' | tail -n1)"
if [[ -z "${key}" ]]; then
    log_error        "${INSTALL_WATCHER}" "configure.key-of-the-bouncer-crowdsec-not-found"
fi
bouncer_cfg="/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml"
if [[ ! -f "${bouncer_cfg}" ]]; then
    log_error        "${INSTALL_WATCHER}" "configure.file-bouncer-absent" "${bouncer_cfg}"
fi
sed -i "s|^[[:space:]]*api_key:.*|api_key: ${key}|" "${bouncer_cfg}"
log_success      "${INSTALL_WATCHER}" "configure.bouncer-nftables-linked-to-the-api-local"

log_info         "${INSTALL_WATCHER}" "configure.activation-of-crowdsec-and-of-the-bouncer"
grep -v '^#' "$(locate_config_file crowdsec/audit.rules)" \
    > /etc/audit/rules.d/w-crowdsec.rules
chmod 640 /etc/audit/rules.d/w-crowdsec.rules
run_silent       "${INSTALL_WATCHER}" "configure.crowdsec.error" augenrules --load

run_silent       "${INSTALL_WATCHER}" "configure.crowdsec.error" systemctl enable --now crowdsec
run_silent       "${INSTALL_WATCHER}" "configure.crowdsec.error" systemctl enable --now crowdsec-firewall-bouncer
run_silent       "${INSTALL_WATCHER}" "configure.crowdsec.error" systemctl restart crowdsec
run_silent       "${INSTALL_WATCHER}" "configure.crowdsec.error" systemctl restart crowdsec-firewall-bouncer
log_success      "${INSTALL_WATCHER}" "configure.crowdsec-and-the-bouncer-enabled"
