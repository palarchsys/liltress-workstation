#!/usr/bin/env bash
# =============================================================================
# File       : core/log/journal.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Load the install journal, the installer, and the copy scripts.
# -----------------------------------------------------------------------------


journal_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${journal_dir}/install-log.sh"
# shellcheck disable=SC1091
source "${journal_dir}/installer.sh"
# shellcheck disable=SC1091
source "${journal_dir}/copy-log.sh"
unset journal_dir
