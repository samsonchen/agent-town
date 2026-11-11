#!/usr/bin/env bash
# Builds the TownWindow add-on for x64 and ARM64 into ../addons/town_window/bin/.
# Needs Visual Studio Build Tools (C++ x64 and ARM64, Windows SDK) and SCons.
# SCONS can point at a SCons outside PATH, for example a private venv.
set -euo pipefail
cd "$(dirname "$0")"
SCONS="${SCONS:-scons}"
for arch in x86_64 arm64; do
  "$SCONS" platform=windows target=template_release arch="$arch" -j8
done
