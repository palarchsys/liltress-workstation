#!/usr/bin/env bash
# =============================================================================
# File       : core/log/journal.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Load the install journal, the installer, and the copy scripts.
# -----------------------------------------------------------------------------


journal_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${journal_directory}/install-log.sh"
# shellcheck disable=SC1091
source "${journal_directory}/installer.sh"
# shellcheck disable=SC1091
source "${journal_directory}/copy-log.sh"
unset journal_directory
