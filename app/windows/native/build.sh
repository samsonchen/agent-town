#!/usr/bin/env bash
# Git Bash wrapper for build.ps1, which does the work. Arguments pass through, for example:
#   bash app/windows/native/build.sh -Arch arm64
#   bash app/windows/native/build.sh -Check
exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$(dirname "$0")")\\build.ps1" "$@"
