#!/usr/bin/env bash
# =============================================================================
# File       : service/aide/configure.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY
G_INSTALL_DIRECTORY="${INSTALL_DIRECTORY}"
export G_INSTALL_DIRECTORY

# shellcheck disable=SC2155
readonly DIR_SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${G_INSTALL_DIRECTORY}/core/lib.sh"
source "${G_INSTALL_DIRECTORY}/config/global.conf"
require_root
get_current_user

log_subtitle     "${INSTALL_WATCHER}" "configure.configuration-help"
log_info         "${INSTALL_WATCHER}" "configure.configuration-of-help-2"
ensure_directory /etc/aide 755
ensure_directory /var/lib/aide 700
sed "s|__HF_BASE__|${G_CONFIG_BASE_DIRECTORY}|g" "$(locate_config_file aide/aide.conf)" > /etc/aide/aide.conf
python3 - /etc/aide/aide.conf "${CURRENT_HOME}" << 'PY'
import sys
from pathlib import Path
path, home = Path(sys.argv[1]), sys.argv[2].rstrip("/")
text = path.read_text()
begin = "# BEGIN Liltress Workstation account"
end = "# END Liltress Workstation account"
old_begin = "# BEGIN High-Fortress User account"
old_end = "# END High-Fortress User account"
lines = text.splitlines()
out = []
skip = False
for line in lines:
    if line.strip() in (begin, old_begin):
        skip = True
        continue
    if line.strip() in (end, old_end):
        skip = False
        continue
    if not skip:
        out.append(line)
names = [
    f"{home}/.ssh/authorized_keys",
    f"{home}/.bashrc",
    f"{home}/.profile",
    f"{home}/.bash_profile",
    f"{home}/.config/autostart",
    f"{home}/.config/systemd/user",
]
block = [begin]
block.extend(f"{name} All" for name in names)
block.append(f"!{home}/.ssh/known_hosts")
block.append(f"!{home}/.ssh/known_hosts.old")
block.append(end)
out.extend(block)
path.write_text("\n".join(out) + "\n")
PY
install -d -m 755 "${G_CONFIG_BASE_DIRECTORY}/bin"
install -m 755 "${DIR_SCRIPT_PATH}/refresh-db.sh" "${G_CONFIG_BASE_DIRECTORY}/bin/aide-refresh-db.sh"
log_success      "${INSTALL_WATCHER}" "configure.help-conf-installed"
log_info         "${INSTALL_WATCHER}" "configure.base-help-after-the-purge-of-the-packages-and-rk"
