#!/usr/bin/env bash
# =============================================================================
# File       : core/host/host.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

host_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${host_dir}/account.sh"
# shellcheck disable=SC1091
source "${host_dir}/ssh.sh"
# shellcheck disable=SC1091
source "${host_dir}/ubuntu.sh"
unset host_dir
