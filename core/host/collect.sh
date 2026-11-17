#!/usr/bin/env bash
# =============================================================================
# File       : core/host/collect.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Save server journals and configuration into one snapshot.
# Note       : A desktop tree stops before any file is written.
# -----------------------------------------------------------------------------


# Each container journal keeps its last lines.
collect_docker_container_logs() {
    local snap="$1"
    local cid="" cname=""
    for cid in $(docker ps -aq 2>/dev/null); do
        cname=$(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null | sed 's#^/##')
        docker logs --tail 2000 "$cid" >"${snap}/docker-logs/${cname:-$cid}.log" 2>&1 || true
    done
}

# Images, networks, and container journals are saved when the engine exists.
collect_docker_status() {
    local snap="$1"
    if command -v docker >/dev/null 2>&1; then
        docker ps -a >"${snap}/docker-ps.txt" 2>&1 || true
        docker network ls >"${snap}/docker-networks.txt" 2>&1 || true
        docker images >"${snap}/docker-images.txt" 2>&1 || true
        mkdir -p "${snap}/docker-logs"
        collect_docker_container_logs "${snap}"
    fi
}

# Readable configuration files are placed under the snapshot.
collect_saved_configs() {
    local snap="$1"
    local cfg=""
    mkdir -p "${snap}/etc"
    for cfg in /etc/nginx/nginx.conf /etc/ssh/sshd_config /etc/fail2ban/jail.local \
        /etc/sysctl.d/90-secure_ips.conf /etc/systemd/journald.conf.d/persistent.conf; do
        if [[ -r "$cfg" ]]; then
            cp -a "$cfg" "${snap}/etc/$(echo "$cfg" | tr '/' '_')" 2>/dev/null || true
        fi
    done
    if [[ -d /etc/nginx/sites-enabled ]]; then
        mkdir -p "${snap}/etc/nginx-sites-enabled"
        cp -a /etc/nginx/sites-enabled/. "${snap}/etc/nginx-sites-enabled/" 2>/dev/null || true
    fi
}

# Compose files are kept. Files ending in .env are deleted.
collect_compose_copies() {
    local snap="$1"
    if [[ -n "${DOCKER_BASE_DIRECTORY:-}" && -d "${DOCKER_BASE_DIRECTORY}" ]]; then
        mkdir -p "${snap}/docker-compose"
        find "${DOCKER_BASE_DIRECTORY}" -name 'docker-compose.yml' -exec cp -a {} "${snap}/docker-compose/" \; 2>/dev/null || true
        find "${snap}/docker-compose" -name '*.env' -delete 2>/dev/null || true
    fi
}

collect_product_logs() {
    local snap="$1"
    if check_workstation; then
        return 0
    fi
    nginx -t >"${snap}/nginx-t.txt" 2>&1 || true
    fail2ban-client status >"${snap}/fail2ban-status.txt" 2>&1 || true
    cscli collections list >"${snap}/crowdsec-collections.txt" 2>&1 || true
    cscli bouncers list >"${snap}/crowdsec-bouncers.txt" 2>&1 || true
    collect_docker_status "${snap}"
    collect_saved_configs "${snap}"
    collect_compose_copies "${snap}"
    copy_unit_journals "${snap}" \
        nginx docker containerd fail2ban crowdsec crowdsec-firewall-bouncer \
        auditd clamav-daemon clamav-freshclam clamonacc postfix ssh redis-server cron apparmor \
        || true
}

collect_workstation_logs() {
    local snap="$1"
    check_workstation || return 0
    {
        echo "=== unbound ==="
        systemctl status unbound --no-pager -l 2>&1 | head -n 80 || true
        echo "=== resolvectl ==="
        resolvectl status 2>&1 | head -n 120 || true
    } >"${snap}/unbound.txt" 2>&1 || true

    if command -v pro >/dev/null 2>&1; then
        pro status 2>&1 | sed -E 's/[A-Za-z0-9]{20,}/[redacted]/g' >"${snap}/ubuntu-pro.txt" || true
    fi

    copy_unit_journals "${snap}" \
        unbound fail2ban crowdsec crowdsec-firewall-bouncer \
        auditd clamav-daemon clamav-freshclam clamonacc postfix ssh cron \
        unattended-upgrades apparmor \
        || true
}
