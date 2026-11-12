#!/usr/bin/env bash
# Git Bash wrapper for run-local.ps1, which does the work. Options pass through, for example:
#   bash app/windows/scripts/run-local.sh -Demo 04 -Zh
#   bash app/windows/scripts/run-local.sh -Live
exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$(dirname "$0")")\run-local.ps1" "$@"
