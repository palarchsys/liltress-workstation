#!/usr/bin/env bash
# =============================================================================
# File       : service/tailscale/common.sh
# Updated at : 2026-11-21
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Bring Tailscale up as an SSH transport and check the link.
# Note       : The auth key stays in the process environment, then is unset.
# -----------------------------------------------------------------------------


require_tailscale_key() {
    local key="${TAILSCALE_AUTH_KEY:-}"
    [[ "${key}" =~ ^tskey-auth-[A-Za-z0-9_-]{10,200}$ ]] || log_error "${INSTALL_WATCHER}" "configure.tailscale.key"
}

check_tailscale_route() {
    ip link show tailscale0 >/dev/null 2>&1 || return 1
    ip route show default 2>/dev/null | grep -q 'dev tailscale0' && return 1
    ip -6 route show default 2>/dev/null | grep -q 'dev tailscale0' && return 1
    python3 "$(locate_python_dir)/tailscale-prefs.py"
}

run_tailscale_up() {
    local host rc
    host="$(hostname -s 2>/dev/null || hostname)"
    set +e
    TS_AUTHKEY="${TAILSCALE_AUTH_KEY}" tailscale up \
        --ssh=false \
        --hostname="${host}" \
        --accept-dns=false \
        --accept-routes=false \
        --advertise-exit-node=false \
        --advertise-routes= \
        --exit-node= \
        --netfilter-mode=off
    rc=$?
    set -e
    unset TS_AUTHKEY
    [[ "${rc}" -eq 0 ]] || log_error "${INSTALL_WATCHER}" "configure.tailscale.bad"
}

run_tailscale_session() {
    require_tailscale_key
    if check_tailscale_route; then
        log_success "${INSTALL_WATCHER}" "configure.tailscale.ready"
        return 0
    fi
    log_info "${INSTALL_WATCHER}" "configure.tailscale.up"
    run_tailscale_up
    check_tailscale_route || log_error "${INSTALL_WATCHER}" "configure.tailscale.bad"
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
    reload_sshd_unit || log_error "${INSTALL_WATCHER}" "configure.tailscale.bad"
    log_success "${INSTALL_WATCHER}" "configure.tailscale.closed"
}
