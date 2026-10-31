#!/usr/bin/env bash
# =============================================================================
# File       : service/ufw/configure.sh
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
get_ssh_port

log_subtitle     "${INSTALL_WATCHER}" "configure.configuration-ufw-desktop-safe"
copy_backup /etc/default/ufw
copy_backup /etc/ufw/before.rules

# shellcheck disable=SC1091
source "$(locate_config_file ufw/policy.conf)"

log_info         "${INSTALL_WATCHER}" "configure.policy-incoming-outgoing-routed" "${W_UFW_DEFAULT_INCOMING}" "${W_UFW_DEFAULT_OUTGOING}" "${W_UFW_DEFAULT_ROUTED}"
run_silent       "${INSTALL_WATCHER}" "configure.ufw.error" ufw default "${W_UFW_DEFAULT_INCOMING}" incoming
run_silent       "${INSTALL_WATCHER}" "configure.ufw.error" ufw default "${W_UFW_DEFAULT_OUTGOING}" outgoing

if grep -q '^DEFAULT_FORWARD_POLICY=' /etc/default/ufw; then
    sed -i "s/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY=\"${W_UFW_FORWARD_POLICY}\"/" /etc/default/ufw
else
    echo "$(get_text configure.default-forward-policy "${W_UFW_FORWARD_POLICY}")" >> /etc/default/ufw
fi
run_silent       "${INSTALL_WATCHER}" "configure.ufw.error" ufw default "${W_UFW_DEFAULT_ROUTED}" routed

if grep -q '^IPT_MODULES=' /etc/default/ufw; then
    if ! awk -F= '/^IPT_MODULES=/{print}' /etc/default/ufw | grep -q "${W_UFW_IPT_EXTRA}"; then
        ipt_val="$(awk -F= '/^IPT_MODULES=/{print substr($0, index($0,"=")+1)}' /etc/default/ufw)"
        ipt_val="${ipt_val#\"}"
        ipt_val="${ipt_val%\"}"
        ipt_val="${ipt_val#\'}"
        ipt_val="${ipt_val%\'}"
        sed -i "s|^IPT_MODULES=.*|IPT_MODULES=\"${ipt_val} ${W_UFW_IPT_EXTRA}\"|" /etc/default/ufw
    fi
else
    echo "$(get_text configure.ipt-modules "${W_UFW_IPT_EXTRA}")" >> /etc/default/ufw
fi
if [[ -f /etc/ufw/sysctl.conf ]] && ! grep -q 'bridge-nf-call-iptables' /etc/ufw/sysctl.conf; then
    printf "$(get_text log.n)" >> /etc/ufw/sysctl.conf
    grep -v '^#' "$(locate_config_file ufw/bridge.conf)" >> /etc/ufw/sysctl.conf
fi

if grep -q '^IPV6=' /etc/default/ufw; then
    sed -i "s/^IPV6=.*/IPV6=${W_UFW_IPV6}/" /etc/default/ufw
else
    echo "$(get_text configure.ipv6 "${W_UFW_IPV6}")" >> /etc/default/ufw
fi

run_silent       "${INSTALL_WATCHER}" "configure.ufw.error" ufw logging "${W_UFW_LOGGING}"

log_info         "${INSTALL_WATCHER}" "configure.ssh-limit-on-the-port-detected-tcp" "${SSH_PORT}"

remove_ufw_marked() {
    local nums n
    mapfile -t nums < <(LANG=C LC_ALL=C ufw status numbered \
        | awk -v open="${W_UFW_SSH_COMMENT_OPEN}" -v lan="${W_UFW_SSH_COMMENT_LAN}" '
            index($0, open) || index($0, lan) {
                if (match($0, /\[[[:space:]]*[0-9]+\]/)) {
                    token = substr($0, RSTART, RLENGTH)
                    gsub(/[^0-9]/, "", token)
                    print token
                }
            }
        ' \
        | sort -nr)
    for n in "${nums[@]+"${nums[@]}"}"; do
        [[ -n "${n}" ]] || continue
        run_silent       "${INSTALL_WATCHER}" "configure.ufw.error" ufw --force delete "${n}"
    done
}

mapfile -t ssh_prefixes < <(ip -o addr show up scope global 2>/dev/null | awk '{print $4}')
if ip -o -6 addr show up scope link 2>/dev/null | grep -q 'fe80:'; then
    ssh_prefixes+=("${W_UFW_LINK_LOCAL}")
fi
kept_prefixes=()
for prefix in "${ssh_prefixes[@]+"${ssh_prefixes[@]}"}"; do
    mask="${prefix##*/}"
    [[ "${mask}" == "0" || "${mask}" == "${prefix}" ]] && continue
    kept_prefixes+=("${prefix}")
done
deduped_prefixes=()
for prefix in "${kept_prefixes[@]+"${kept_prefixes[@]}"}"; do
    already=0
    for seen_prefix in "${deduped_prefixes[@]+"${deduped_prefixes[@]}"}"; do
        if [[ "${seen_prefix}" == "${prefix}" ]]; then
            already=1
            break
        fi
    done
    if [[ "${already}" -eq 0 ]]; then
        deduped_prefixes+=("${prefix}")
    fi
done
kept_prefixes=()
for prefix in "${deduped_prefixes[@]+"${deduped_prefixes[@]}"}"; do
    kept_prefixes+=("${prefix}")
done

if [[ ${#kept_prefixes[@]} -eq 0 ]]; then
    if ! LANG=C LC_ALL=C ufw status | grep -qF "${W_UFW_SSH_COMMENT_OPEN}"; then
        run_silent       "${INSTALL_WATCHER}" "configure.ufw.error" ufw limit "${SSH_PORT}/tcp" comment "${W_UFW_SSH_COMMENT_OPEN}"
    fi
    log_warn         "${INSTALL_WATCHER}" "configure.no-pr-fixe-connected-ssh-stays-opened-on-all-the"
else
    remove_ufw_marked
    for prefix in "${kept_prefixes[@]}"; do
        run_silent       "${INSTALL_WATCHER}" "configure.ufw.error" ufw limit from "${prefix}" to any port "${SSH_PORT}" proto tcp comment "${W_UFW_SSH_COMMENT_LAN}"
    done
    log_success      "${INSTALL_WATCHER}" "configure.ssh-limited-to-the-pr-fixes-connect-s" "${kept_prefixes[*]}"
fi

run_silent       "${INSTALL_WATCHER}" "configure.ufw.error" ufw allow in on lo
run_silent       "${INSTALL_WATCHER}" "configure.ufw.error" ufw allow out on lo

log_subtitle     "${INSTALL_WATCHER}" "configure.activation-ufw"
log_info         "${INSTALL_WATCHER}" "configure.activation-of-ufw"
run_silent       "${INSTALL_WATCHER}" "configure.ufw.error" ufw --force enable
if ! LANG=C LC_ALL=C ufw status | grep -qw "Status: active"; then
    log_error        "${INSTALL_WATCHER}" "configure.ufw-is-not-active-after-enable" "$(LANG=C LC_ALL=C ufw status)"
fi
log_success      "${INSTALL_WATCHER}" "configure.ufw-enabled-outgoing-allow"
bash "${G_INSTALL_DIRECTORY}/service/ufw/egress.sh" "${INSTALL_WATCHER}" "${G_INSTALL_DIRECTORY}"
