#!/usr/bin/env bash
# =============================================================================
# File       : core/log/color.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================


set_color_blue()    { printf '\e[34m%s\e[0m\n' "$*" >&2; }

set_color_violet()  { printf '\e[35m%s\e[0m\n' "$*" >&2; }

set_color_red()     { printf '\e[31m%s\e[0m\n' "$*" >&2; }

set_color_yellow()  { printf '\e[33m%s\e[0m\n' "$*" >&2; }

set_color_green()   { printf '\e[32m%s\e[0m\n' "$*" >&2; }

set_color_orange()  { printf '\e[38;5;208m%s\e[0m\n' "$*" >&2; }
