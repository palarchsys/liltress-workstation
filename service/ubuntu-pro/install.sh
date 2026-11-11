#!/usr/bin/env bash
# =============================================================================
# File       : service/ubuntu-pro/install.sh
# Updated at : 2026-11-07
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

if [[ -z "${UBUNTU_BASE_VERSION:-}" ]]; then
    get_operating_system
fi

token="${UBUNTU_PRO_TOKEN:-}"
token="${token// /}"
attached=0
if check_workstation || [[ -n "${token}" ]]; then
    log_info         "${INSTALL_WATCHER}" "install.installation-of-the-client-ubuntu-pro"
    run_silent_apt   "${INSTALL_WATCHER}" "install -y ubuntu-pro-client" "install.ubuntu-pro.error"

    log_info         "${INSTALL_WATCHER}" "install.check-of-the-attachment-ubuntu-pro"
    if check_ubuntu_pro; then
        log_success      "${INSTALL_WATCHER}" "install.ubuntu-pro-already-attached"
        attached=1
    else
        if [[ -z "${token}" ]]; then
            log_error        "${INSTALL_WATCHER}" "install.ubuntu-pro-missing-token-in-secrets-conf-rerun-b" "${INSTALL_DIRECTORY}"
        fi
        log_info         "${INSTALL_WATCHER}" "install.attachment-of-ubuntu-pro"
        attach_out=$(pro attach "${token}" 2>&1) && attach_rc=0 || attach_rc=$?
        if [[ "${attach_rc}" -eq 0 ]]; then
            log_success      "${INSTALL_WATCHER}" "install.ubuntu-pro-machine-attached"
        elif echo "${attach_out}" | grep -qiE 'already attached'; then
            log_success      "${INSTALL_WATCHER}" "install.ubuntu-pro-already-attached"
        else
            log_error        "${INSTALL_WATCHER}" "install.ubuntu-pro-attach-a-failed-required" "${attach_out}"
        fi
        if ! check_ubuntu_pro; then
            log_error        "${INSTALL_WATCHER}" "install.ubuntu-pro-the-machine-is-not-attached-after-pro"
        fi
        attached=1
    fi
fi

if check_ubuntu_lts; then
    if [[ "${attached}" -eq 1 ]]; then
        for svc in esm-infra esm-apps; do
            log_info         "${INSTALL_WATCHER}" "install.activation-of-ubuntu-pro" "${svc}"
            en_out=$(pro enable "${svc}" --assume-yes 2>&1) && en_rc=0 || en_rc=$?
            if [[ "${en_rc}" -eq 0 ]] || echo "${en_out}" | grep -qiE 'already enabled'; then
                log_success      "${INSTALL_WATCHER}" "install.ubuntu-pro-enabled" "${svc}"
            elif check_workstation; then
                log_warn         "${INSTALL_WATCHER}" "install.ubuntu-pro-not-enabled-installation-continued" "${svc}"
                log_debug        "${INSTALL_WATCHER}" "install.install.debug" "${en_out}"
            else
                log_error        "${INSTALL_WATCHER}" "install.ubuntu-pro.error" "${en_out}"
            fi
        done

        log_info         "${INSTALL_WATCHER}" "install.activation-of-livepatch"
        lp_out=$(pro enable livepatch --assume-yes 2>&1) && lp_rc=0 || lp_rc=$?
        if [[ "${lp_rc}" -eq 0 ]] || echo "${lp_out}" | grep -qiE 'already enabled'; then
            log_success      "${INSTALL_WATCHER}" "install.ubuntu-pro-livepatch-enabled"
        else
            log_warn         "${INSTALL_WATCHER}" "install.ubuntu-pro-livepatch-not-enabled-installation-co"
            log_debug        "${INSTALL_WATCHER}" "install.install.debug.2" "${lp_out}"
        fi
    fi
else
    log_info         "${INSTALL_WATCHER}" "install.intermediate-version-esm-infra-esm-apps-and-live"
fi

if [[ "${attached}" -eq 1 ]]; then
    log_info         "${INSTALL_WATCHER}" "install.installation-of-ubuntu-pro"
    log_success      "${INSTALL_WATCHER}" "install.ubuntu-pro-installed"
fi
