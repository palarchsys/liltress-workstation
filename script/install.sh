#!/usr/bin/env bash
# =============================================================================
# File       : script/install.sh
# Updated at : 2026-11-22
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Install the product tree from the GitHub archive.
# Note       : Prepared configuration returns after the archive is fetched.
# Note       : A missing terminal stops before the tree is replaced.
# -----------------------------------------------------------------------------


set -euo pipefail

INSTALL_WATCHER="${INSTALL_WATCHER:-BASH}"
export INSTALL_WATCHER

REPO_URL="${REPO_URL:-https://github.com/palarchsys/liltress-workstation}"
BRANCH="${BRANCH:-main}"
INSTALL_ROOT="${INSTALL_ROOT:-/opt/liltress-workstation}"

if [[ "${EUID}" -ne 0 ]]; then
    if declare -F get_text >/dev/null 2>&1; then
        printf '%s\n' "$(get_text install.this-script-must-be-executed-as-root-sudo)" >&2
    else
        printf '%s\n' "This script must be run as root (sudo)." >&2
    fi
    exit 1
fi

if [[ -z "${INSTALL_ROOT}" || "${INSTALL_ROOT}" != /opt/* || "${INSTALL_ROOT}" == "/opt" || "${INSTALL_ROOT}" == "/" || "${INSTALL_ROOT}" == *..* || "${INSTALL_ROOT}" == *[[:space:]]* ]]; then
    if declare -F get_text >/dev/null 2>&1; then
        printf '%s\n' "$(get_text install.root-of-install-rejected "${INSTALL_ROOT}")" >&2
    else
        printf '%s\n' "Install root rejected: ${INSTALL_ROOT}" >&2
    fi
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq ca-certificates git >/dev/null 2>&1

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "${tmp}/keep"

save_prepared() {
    local root="$1"
    if [[ -f "${root}/config/global.conf" ]] && grep -q '^CONFIG_PREPARED=1$' "${root}/config/global.conf"; then
        cp -a "${root}/config/global.conf" "${tmp}/keep/global.conf"
        if [[ -f "${root}/config/user.conf" ]]; then
            cp -a "${root}/config/user.conf" "${tmp}/keep/user.conf"
        fi
    fi
    if [[ ! -f "${tmp}/keep/secrets.conf" && -f "${root}/config/secrets.conf" ]]; then
        cp -a "${root}/config/secrets.conf" "${tmp}/keep/secrets.conf"
    fi
}

save_scan_skip() {
    local root="$1"
    if [[ -f "${tmp}/keep/scan-skip.paths" ]]; then
        return 0
    fi
    if [[ -f "${root}/config/service/clamav/scan-skip.paths" ]] && ! grep -q '__HOME__' "${root}/config/service/clamav/scan-skip.paths"; then
        cp -a "${root}/config/service/clamav/scan-skip.paths" "${tmp}/keep/scan-skip.paths"
    fi
}

save_runtime() {
    local root="$1"
    local name
    for name in docker secrets; do
        if [[ ! -e "${tmp}/keep/${name}" && -d "${root}/${name}" ]]; then
            mv "${root}/${name}" "${tmp}/keep/${name}"
        fi
    done
    if [[ -d "${root}/cron" ]]; then
        mkdir -p "${tmp}/keep/cron"
        for name in cron_logs security_logs alerts archives quarantine; do
            if [[ -d "${root}/cron/${name}" && ! -e "${tmp}/keep/cron/${name}" ]]; then
                mv "${root}/cron/${name}" "${tmp}/keep/cron/${name}"
            fi
        done
    fi
}

restore_kept() {
    if [[ -f "${tmp}/keep/global.conf" ]]; then
        cp -a "${tmp}/keep/global.conf" "${INSTALL_ROOT}/config/global.conf"
    fi
    if [[ -f "${tmp}/keep/user.conf" ]]; then
        cp -a "${tmp}/keep/user.conf" "${INSTALL_ROOT}/config/user.conf"
    fi
    if [[ -f "${tmp}/keep/secrets.conf" ]]; then
        cp -a "${tmp}/keep/secrets.conf" "${INSTALL_ROOT}/config/secrets.conf"
        chmod 600 "${INSTALL_ROOT}/config/secrets.conf"
    fi
    if [[ -f "${tmp}/keep/scan-skip.paths" ]]; then
        mkdir -p "${INSTALL_ROOT}/config/service/clamav"
        cp -a "${tmp}/keep/scan-skip.paths" "${INSTALL_ROOT}/config/service/clamav/scan-skip.paths"
        chmod 644 "${INSTALL_ROOT}/config/service/clamav/scan-skip.paths"
    fi
    apply_kept_runtime
}

# Saved runtime directories return beside the configuration files.
apply_kept_runtime() {
    local name
    for name in docker secrets; do
        if [[ -d "${tmp}/keep/${name}" ]]; then
            rm -rf "${INSTALL_ROOT:?}/${name:?}"
            mv "${tmp}/keep/${name}" "${INSTALL_ROOT}/${name}"
        fi
    done
    if [[ -d "${tmp}/keep/cron" ]]; then
        mkdir -p "${INSTALL_ROOT}/cron"
        for name in cron_logs security_logs alerts archives quarantine; do
            if [[ -d "${tmp}/keep/cron/${name}" ]]; then
                rm -rf "${INSTALL_ROOT:?}/cron/${name:?}"
                mv "${tmp}/keep/cron/${name}" "${INSTALL_ROOT}/cron/${name}"
            fi
        done
    fi
}

# A missing terminal stops before the tree is replaced.
stop_without_terminal() {
    if declare -F log_info >/dev/null 2>&1; then
        log_info "${INSTALL_WATCHER}" "install.no-terminal"
    elif declare -F get_text >/dev/null 2>&1; then
        printf '%s\n' "$(get_text install.no-terminal)" >&2
    else
        printf '%s\n' "No terminal for the question. Stopped." >&2
    fi
    exit 0
}

# Any answer other than O stops. An open frame is closed first.
stop_install() {
    if [[ "${STEP_TREE:-0}" == "1" ]]; then
        close_step_tree
    fi
    if [[ "${SECTION_OPEN:-0}" == "1" ]]; then
        show_section_close
    fi
    if declare -F log_info >/dev/null 2>&1; then
        log_info "${INSTALL_WATCHER}" "install.stopped"
    elif declare -F get_text >/dev/null 2>&1; then
        printf '%s\n' "$(get_text install.stopped)" >&2
    else
        printf '%s\n' "Stopped." >&2
    fi
    exit 0
}

# Loaded display draws the titled question.
ask_replace_known() {
    local title=""
    clear
    if [[ -f "${INSTALL_DIRECTORY}/script/verify/workstation.sh" ]]; then
        title="$(get_text log.liltress-workstation-hardening-workstation)"
    else
        title="$(get_text log.liltress-choice-of-the-profile)"
    fi
    ask_yes "$(get_text install.continue-o-n)" "${title}" || stop_install
}

# The replace question stays outside the installation section.
ask_replace_continue() {
    local answer=""
    if [[ ! -r /dev/tty ]]; then
        stop_without_terminal
    fi
    if declare -F ask_yes >/dev/null 2>&1 && declare -F get_text >/dev/null 2>&1 && declare -F show_title_box >/dev/null 2>&1; then
        ask_replace_known
        return 0
    fi
    printf '%s' "Continue the installation? [O/N] " >&2
    IFS= read -r answer </dev/tty || answer=""
    case "${answer}" in
        O | o) return 0 ;;
    esac
    printf '%s\n' "Stopped." >&2
    exit 0
}

# Clone output would sit above the frame.
show_product_title() {
    local title=""
    clear
    if [[ -f "${INSTALL_DIRECTORY}/script/verify/workstation.sh" ]]; then
        title="$(get_text log.liltress-workstation-hardening-workstation)"
    else
        title="$(get_text log.liltress-choice-of-the-profile)"
    fi
    show_title_box "${title}"
    printf '\n' >&2
}

# The home directory stays out of the two lines.
show_install_identity() {
    get_operating_system
    get_current_user
    log_info "${INSTALL_WATCHER}" "install.user" "${CURRENT_USER}"
    log_info "${INSTALL_WATCHER}" "install.os" "${OS_PRETTY}"
}

# O continues. Any other answer stops.
ask_install_step() {
    ask_yes "$1" || stop_install
}

# The check runs only after O. The result line stays in this tree.
ask_config_gate() {
    open_step_tree "script/config-check.sh"
    mark_section_step
    ask_install_step "$(get_text install.check.ask)"
    if bash "${INSTALL_ROOT}/script/configure.sh" --check; then
        log_success "${INSTALL_WATCHER}" "install.check.valid"
        return 0
    fi
    log_success "${INSTALL_WATCHER}" "install.check.invalid"
    return 1
}

# The runner is a new process. It closes this line, then its own section.
launch_runner() {
    open_step_tree "script/run.sh"
    mark_section_step
    ask_install_step "$(get_text install.run.ask)"
    log_success "${INSTALL_WATCHER}" "install.run.started"
    export STEP_TREE STEP_PENDING SECTION_OPEN SECTION_HAD_STEP
    cd "${INSTALL_ROOT}"
    exec bash "${INSTALL_ROOT}/script/run.sh"
}

# A failed check closes the section and names the configurator.
launch_configurator() {
    close_step_tree
    set_step_hidden "$(get_text install.configuration.title)"
    show_closing_note "$(get_text install.configuration.launch)" "$(get_text install.configuration.command)"
    exec bash "${INSTALL_ROOT}/script/configure.sh"
}

mkdir -p "${INSTALL_ROOT}"
save_prepared "${INSTALL_ROOT}"
save_scan_skip "${INSTALL_ROOT}"
if [[ -f "${INSTALL_ROOT}/src/liltress" ]]; then
    save_prepared "${INSTALL_ROOT}/src"
    save_scan_skip "${INSTALL_ROOT}/src"
    save_runtime "${INSTALL_ROOT}/src"
fi

if [[ -n "$(find "${INSTALL_ROOT}" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    if [[ -f "${INSTALL_ROOT}/core/boot/lib.sh" && -f "${INSTALL_ROOT}/core/boot/bootstrap.sh" && -f "${INSTALL_ROOT}/config/global.conf" ]]; then
        INSTALL_DIRECTORY="${INSTALL_ROOT}"
        # shellcheck disable=SC1091
        source "${INSTALL_DIRECTORY}/core/boot/lib.sh" || true
        # shellcheck disable=SC1091
        source "${INSTALL_DIRECTORY}/config/global.conf" || true
        if declare -F read_language_file >/dev/null 2>&1; then
            read_language_file "${INSTALL_DIRECTORY}/config/global.conf" || true
        fi
    fi
    ask_replace_continue
fi

if [[ -d "${INSTALL_ROOT}/.git" ]]; then
    git -C "${INSTALL_ROOT}" fetch -q --depth 1 origin "${BRANCH}"
    trap - EXIT
    save_runtime "${INSTALL_ROOT}"
    git -C "${INSTALL_ROOT}" clean -fdq
    git -C "${INSTALL_ROOT}" checkout -q -f -B "${BRANCH}" FETCH_HEAD
else
    trap - EXIT
    save_runtime "${INSTALL_ROOT}"
    find "${INSTALL_ROOT}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    git clone -q --depth 1 --branch "${BRANCH}" "${REPO_URL}" "${INSTALL_ROOT}"
fi

if [[ ! -f "${INSTALL_ROOT}/config/global.conf" || ! -f "${INSTALL_ROOT}/liltress" ]]; then
    if declare -F log_error >/dev/null 2>&1; then
        log_error "${INSTALL_WATCHER}" "install.archive-github-invalid-config-global-conf-absent"
    elif declare -F get_text >/dev/null 2>&1; then
        printf '%s\n' "$(get_text install.archive-github-invalid-config-global-conf-absent)" >&2
        exit 1
    else
        printf '%s\n' "Invalid GitHub archive (config/global.conf absent)." >&2
        exit 1
    fi
fi

restore_kept
trap 'rm -rf "$tmp"' EXIT
rm -rf "${INSTALL_ROOT:?}/src"
chmod 755 "${INSTALL_ROOT}/liltress"
INSTALL_DIRECTORY="${INSTALL_ROOT}" bash -c '
    set -euo pipefail
    # shellcheck disable=SC1091
    source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
    # shellcheck disable=SC1091
    source "${INSTALL_DIRECTORY}/config/global.conf"
    set_tree_modes
'

INSTALL_DIRECTORY="${INSTALL_ROOT}"
# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/config/global.conf"
read_language_file "${INSTALL_DIRECTORY}/config/global.conf"

show_product_title
show_install_identity
printf '\n' >&2
set_step_visible "$(get_text install.section)"
if ask_config_gate; then
    launch_runner
fi
launch_configurator
