#!/usr/bin/env bash
# =============================================================================
# File       : service/crowdsec/install.sh
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

log_subtitle     "${INSTALL_WATCHER}" "install.repository-crowdsec"
log_info         "${INSTALL_WATCHER}" "install.record-of-the-repository-crowdsec"
install -d -m 755 /etc/apt/keyrings
CROWDSEC_KEY="/etc/apt/keyrings/crowdsec_crowdsec-archive-keyring.gpg"
CROWDSEC_LIST="/etc/apt/sources.list.d/crowdsec_crowdsec.list"
curl -fsSL https://packagecloud.io/crowdsec/crowdsec/gpgkey | gpg --dearmor -o "${CROWDSEC_KEY}"
chmod 644 "${CROWDSEC_KEY}"
sed "s|__KEY__|${CROWDSEC_KEY}|g" "$(locate_config_file crowdsec/package.list)" \
    | grep -v '^#' > "${CROWDSEC_LIST}"
chmod 644 "${CROWDSEC_LIST}"

grep -v '^#' "$(locate_config_file crowdsec/preferences.conf)" > /etc/apt/preferences.d/crowdsec
chmod 644 /etc/apt/preferences.d/crowdsec
run_silent_apt   "${INSTALL_WATCHER}" "update" "install.crowdsec.error"
log_success      "${INSTALL_WATCHER}" "install.repository-crowdsec-saved"

log_subtitle     "${INSTALL_WATCHER}" "install.installation-of-crowdsec-2"
log_info         "${INSTALL_WATCHER}" "install.installation-of-crowdsec-2"
run_silent_apt   "${INSTALL_WATCHER}" "install -y crowdsec crowdsec-firewall-bouncer-nftables" "install.crowdsec.error"
cs_ver="$(dpkg-query -W -f '${Version}' crowdsec 2>/dev/null || true)"
if [[ "${cs_ver}" == 1.4.* ]]; then
    log_error        "${INSTALL_WATCHER}" "install.crowdsec-comes-of-the-repository-ubuntu-no-packa" "${cs_ver}"
fi
run_silent       "${INSTALL_WATCHER}" "install.crowdsec.error" systemctl daemon-reload
log_success      "${INSTALL_WATCHER}" "install.crowdsec-installed" "${cs_ver}"
