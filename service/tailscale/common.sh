#!/usr/bin/env bash
# =============================================================================
# File       : service/tailscale/common.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Bring Tailscale up as an SSH transport and check the link.
# Note       : The auth key is a mode 600 file passed to --auth-key, then removed.
# Note       : Ordinary traffic keeps the host default route, including the VPN.
# -----------------------------------------------------------------------------


require_tailscale_key() {
    local key="${TAILSCALE_AUTH_KEY:-}"
    [[ "${key}" =~ ^tskey-auth-[A-Za-z0-9_-]{10,200}$ ]] || log_error "${INSTALL_WATCHER}" "configure.tailscale.key"
}

check_tailscale_route() {
    ip link show tailscale0 >/dev/null 2>&1 || return 1
    ip route show default 2>/dev/null | grep -q 'dev tailscale0' && return 1
    ip -6 route show default 2>/dev/null | grep -q 'dev tailscale0' && return 1
    python3 "$(locate_python_directory)/tailscale-prefs.py"
}

# The CLI writes this notice on stdout. UFW already owns the firewall.
strip_tailscale_notice() {
    grep -v 'netfilter=off; configure iptables yourself' "$1" || true
}

run_tailscale_up() {
    local host rc key_file out_file err_file
    host="$(hostname -s 2>/dev/null || hostname)"
    key_file="$(mktemp)"
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    chmod 600 "${key_file}"
    printf '%s\n' "${TAILSCALE_AUTH_KEY}" >"${key_file}"
    set +e
    tailscale up \
        --auth-key="file:${key_file}" \
        --ssh=false \
        --hostname="${host}" \
        --accept-dns=false \
        --accept-routes=false \
        --advertise-exit-node=false \
        --advertise-routes= \
        --exit-node= \
        --netfilter-mode=off \
        >"${out_file}" 2>"${err_file}"
    rc=$?
    set -e
    strip_tailscale_notice "${out_file}"
    strip_tailscale_notice "${err_file}" >&2
    rm -f -- "${key_file}" "${out_file}" "${err_file}"
    unset TAILSCALE_AUTH_KEY
    [[ "${rc}" -eq 0 ]] || log_error "${INSTALL_WATCHER}" "configure.tailscale.bad"
}

# tailscaled restores its own policy rules each time the daemon starts.
install_tailscale_route_unit() {
    local directory="/etc/systemd/system/tailscaled.service.d"
    local drop="${directory}/liltress-routes.conf"
    local script="${INSTALL_DIRECTORY}/service/tailscale/apply-routes.sh"
    local want have
    [[ -f "${script}" ]] || log_error "${INSTALL_WATCHER}" "configure.tailscale.bad"
    install -d -m 755 "${directory}"
    want="$(printf '[Service]\nExecStartPost=-/bin/bash %s\n' "${script}")"
    if [[ -f "${drop}" ]]; then
        have="$(cat "${drop}")"
        [[ "${have}" == "${want}" ]] && return 0
    fi
    printf '%s\n' "${want}" >"${drop}"
    chmod 644 "${drop}"
    systemctl daemon-reload >/dev/null 2>&1 || true
}

run_tailscale_session() {
    require_tailscale_key
    if ! check_tailscale_route; then
        log_info "${INSTALL_WATCHER}" "configure.tailscale.up"
        run_tailscale_up
        check_tailscale_route || log_error "${INSTALL_WATCHER}" "configure.tailscale.bad"
    fi
    bash "${INSTALL_DIRECTORY}/service/tailscale/apply-routes.sh" \
        || log_error "${INSTALL_WATCHER}" "configure.tailscale.bad"
    install_tailscale_route_unit
    log_success "${INSTALL_WATCHER}" "configure.tailscale.ready"
}

clear_public_ssh() {
    local nums n
    ip link show tailscale0 >/dev/null 2>&1 || log_error "${INSTALL_WATCHER}" "configure.tailscale.bad"
    mapfile -t nums < <(LANG=C LC_ALL=C LANGUAGE=C ufw status numbered | awk -v port="${SSH_PORT}/tcp" '
        index($0, "tailscale0") { next }
        index($0, port) == 0 { next }
        $0 !~ /ALLOW IN/ && $0 !~ /LIMIT IN/ { next }
        {
            if (match($0, /\[[[:space:]]*[0-9]+\]/)) {
                token = substr($0, RSTART, RLENGTH)
                gsub(/[^0-9]/, "", token)
                print token
            }
        }
    ' | sort -nr)
    for n in "${nums[@]+"${nums[@]}"}"; do
        [[ -n "${n}" ]] || continue
        ufw --force delete "${n}" >/dev/null 2>&1 || true
    done
    sshd -t || log_error "${INSTALL_WATCHER}" "configure.sshd-t-a-failed-drop-in-removed"
    run_sshd_reload || log_error "${INSTALL_WATCHER}" "configure.tailscale.bad"
    log_success "${INSTALL_WATCHER}" "configure.tailscale.closed"
}
