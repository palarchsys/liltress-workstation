#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/watchdog.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

if ! declare -F get_text >/dev/null 2>&1; then
    text_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    for text_candidate in \
        "${text_here}/../log/log.sh" \
        "${CONFIG_BASE_DIRECTORY:-}/core/log/log.sh" \
        "${BASE:-}/core/log/log.sh" \
        "${INSTALL_DIRECTORY:-}/core/log/log.sh" \
        "${PRODUCT_ROOT:-}/core/log/log.sh" \
        "${PRODUCT_ROOT:-}/../share/core/log/log.sh"
    do
        if [[ -n "${text_candidate}" && -f "${text_candidate}" ]]; then
            # shellcheck disable=SC1090
            source "${text_candidate}"
            break
        fi
    done
    unset text_candidate text_here
fi

load_watchdog_parts() {
    local watchdog_dir watchdog_part
    watchdog_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    for watchdog_part in \
        base.sh crash.sh limit.sh excerpt.sh clamav.sh debsums.sh \
        quarantine.sh egress.sh advice.sh deliver.sh \
        decide.sh remedy.sh pack.sh report.sh
    do
        if [[ -f "${watchdog_dir}/${watchdog_part}" ]]; then
            # shellcheck disable=SC1090
            source "${watchdog_dir}/${watchdog_part}"
        fi
    done
}

load_watchdog_parts
