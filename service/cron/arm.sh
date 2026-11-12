#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/arm.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

# -----------------------------------------------------------------------------
# Purpose    : Arm the workstation timers through the shared launcher.
# Note       : enable.sh calls this script with enable. The install plan calls it to start.
# -----------------------------------------------------------------------------

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
arm_mode="${4:-start}"
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
arm_lib=""
for candidate in \
    "${here}/arm-units.sh" \
    "${here}/../../../share/service/cron/arm-units.sh"
do
    if [[ -f "${candidate}" ]]; then
        arm_lib="${candidate}"
        break
    fi
done
if [[ -z "${arm_lib}" ]]; then
    printf 'arm-units.sh introuvable depuis %s\n' "${here}" >&2
    exit 1
fi
exec bash "${arm_lib}" "${INSTALL_WATCHER}" "${INSTALL_DIRECTORY}" "${arm_mode}" configure.cron.error.8 \
    w-boot-chain.timer:configure.cron.error.9 \
    w-idle-scan.timer:configure.cron.error.10 \
    w-reboot-notice.timer:configure.cron.error.11 \
    w-periodic-scan.timer:configure.cron.error.12 \
    w-hourly-scan.timer:configure.cron.error.13
