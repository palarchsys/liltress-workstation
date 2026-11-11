#!/usr/bin/env bash
# =============================================================================
# File       : service/rngd/install.sh
# Updated at : 2026-11-07
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info         "${INSTALL_WATCHER}" "install.installation-of-the-packages"
run_silent_apt   "${INSTALL_WATCHER}" "install -y rng-tools-debian" "install.rngd.error"
log_info         "${INSTALL_WATCHER}" "install.load-virtio-rng-hwrng-kvm"
tee /etc/modules-load.d/hwrng.conf > /dev/null << 'EOF'
virtio_rng
EOF
run_optional     "${INSTALL_WATCHER}" "install.rngd.error" modprobe virtio_rng
run_optional     "${INSTALL_WATCHER}" "install.rngd.error" modprobe tpm_rng

log_info         "${INSTALL_WATCHER}" "install.configuration-rng-tools-debian-hwrng-rngd"
rng_select=""
if [[ -r /sys/class/misc/hw_random/rng_available ]]; then
    rng_select="$(tr ' ' '\n' < /sys/class/misc/hw_random/rng_available | awk 'NF && $0 != "none" { print; exit }')"
fi
{
    echo "$(get_text install.liltress-lynis-cryp-8004-hw-rng-rngd)"
    echo "$(get_text install.hrngdevice-set-skipdevice-debian-applies-more)"
    echo "$(get_text install.hrngdevice-dev-hwrng)"
    if [[ -n "${rng_select}" ]]; then
        echo "$(get_text install.hrngselect "${rng_select}")"
    fi
} > /etc/default/rng-tools-debian
chmod 644 /etc/default/rng-tools-debian
if [[ -n "${rng_select}" && -w /sys/class/misc/hw_random/rng_current ]]; then
    printf '%s' "${rng_select}" > /sys/class/misc/hw_random/rng_current || true
fi

run_silent       "${INSTALL_WATCHER}" "install.rngd.error" systemctl enable rng-tools-debian
rng_start_out=$(systemctl restart rng-tools-debian.service 2>&1) && rng_start_rc=0 || rng_start_rc=$?
rng_result=$(systemctl show rng-tools-debian.service -p Result --value 2>/dev/null || true)

if systemctl is-active --quiet rng-tools-debian && pgrep -x rngd >/dev/null; then
    log_success      "${INSTALL_WATCHER}" "install.rng-tools-debian-rngd-active-hwrng-feeds-the-poo"
elif [[ ! -c /dev/hwrng ]]; then
    log_info         "${INSTALL_WATCHER}" "install.no-dev-hwrng-entropy-via-haveged"
    log_success      "${INSTALL_WATCHER}" "install.rng-tools-debian-no-hwrng-hardware-active-havege"
elif [[ "${rng_result}" == "exec-condition" ]]; then
    log_error        "${INSTALL_WATCHER}" "install.rng-tools-debian-skipdevice-despite-hrngdevice-d" "${rng_result}" "$(systemctl status rng-tools-debian.service --no-pager -l | tail -n 25)"
else
    log_error        "${INSTALL_WATCHER}" "install.rng-tools-debian-did-not-started-rc-result" "${rng_start_rc}" "${rng_result}" "${rng_start_out}" "$(systemctl status rng-tools-debian.service --no-pager -l | tail -n 25)"
fi
