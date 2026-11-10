#!/bin/bash
# Builds AgentTown.app and AgentTown-<version>.dmg, signed with a Developer ID and notarized by
# Apple, so it opens on any Mac (macOS 15 or later) without Xcode and without "Open Anyway".
#
#   app/macos/scripts/release.sh             build, sign, notarize, make the .dmg
#   app/macos/scripts/release.sh --publish   the same, then a draft GitHub release v<version>
#   app/macos/scripts/release.sh --unsigned  a local test build: no Developer ID, no notarization
#
# One-time setup on the Mac that releases (no secrets are ever stored in the repo):
#   1. Xcode > Settings > Accounts: add the Apple Account of the developer team;
#      Manage Certificates > + > Developer ID Application.
#   2. An app-specific password from account.apple.com, saved in the keychain with:
#      xcrun notarytool store-credentials agent-town-notary --apple-id <email> --team-id <TEAM ID>
#
# Settings (environment):
#   VERSION         default: the town-link plugin's version (plugin/.claude-plugin/plugin.json)
#   BUNDLE_ID       default: ai.careactive.agenttown
#   SIGN_IDENTITY   default: the one "Developer ID Application" certificate in the keychain
#   NOTARY_PROFILE  default: agent-town-notary
#   ARCHS           default: "arm64 x86_64" (a universal app)
set -euo pipefail

MODE=release
PUBLISH=0
for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=1 ;;
    --unsigned) MODE=unsigned ;;
    -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

PKG="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$PKG/../.." && pwd)"
OUT="$PKG/build/release"
APP="$OUT/AgentTown.app"

VERSION="${VERSION:-$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$REPO/plugin/.claude-plugin/plugin.json")}"
BUILD_NUMBER="$(git -C "$REPO" rev-list --count HEAD)"
BUNDLE_ID="${BUNDLE_ID:-ai.careactive.agenttown}"
NOTARY_PROFILE="${NOTARY_PROFILE:-agent-town-notary}"
ARCHS="${ARCHS:-arm64 x86_64}"
DMG="$OUT/AgentTown-$VERSION.dmg"

step() { printf '\n==> %s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# -- Signing identity --------------------------------------------------------------------------
if [ "$MODE" = release ]; then
  if [ -z "${SIGN_IDENTITY:-}" ]; then
    ids="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | sort -u)"
    count="$(printf '%s' "$ids" | grep -c . || true)"
    [ "$count" -eq 1 ] || fail "found $count Developer ID Application certificates; set SIGN_IDENTITY (or use --unsigned for a test build)"
    SIGN_IDENTITY="$ids"
  fi
  echo "Signing as: $SIGN_IDENTITY"
fi
[ "$PUBLISH" -eq 0 ] || [ "$MODE" = release ] || fail "--publish needs a signed build"
if [ "$PUBLISH" -eq 1 ]; then
  [ -z "$(git -C "$REPO" status --porcelain)" ] || fail "commit your changes before publishing"
  command -v gh >/dev/null || fail "--publish needs the GitHub CLI (gh)"
fi

# -- Build -------------------------------------------------------------------------------------
step "Building AgentTown $VERSION ($BUILD_NUMBER) for $ARCHS"
arch_flags=()
for a in $ARCHS; do arch_flags+=(--arch "$a"); done
(cd "$PKG" && swift build -c release --product AgentTown "${arch_flags[@]}")
BIN_DIR="$(cd "$PKG" && swift build -c release --product AgentTown "${arch_flags[@]}" --show-bin-path)"
[ -x "$BIN_DIR/AgentTown" ] || fail "no executable in $BIN_DIR"
[ -d "$BIN_DIR/AgentTown_AgentTown.bundle" ] || fail "no resource bundle in $BIN_DIR"

# -- Assemble the .app -------------------------------------------------------------------------
step "Assembling $APP"
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/AgentTown" "$APP/Contents/MacOS/AgentTown"
# The resources, with any symbolic link replaced by what it points to.
cp -RL "$BIN_DIR/AgentTown_AgentTown.bundle" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>AgentTown</string>
  <key>CFBundleDisplayName</key><string>agent-town</string>
  <key>CFBundleExecutable</key><string>AgentTown</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hant</string></array>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <!-- A menu bar app: no Dock icon. -->
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© $(date +%Y) Care Active</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# -- Sign --------------------------------------------------------------------------------------
if [ "$MODE" = release ]; then
  step "Signing (hardened runtime)"
  codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$APP"
else
  step "Signing ad hoc (local test build only)"
  codesign --force --sign - "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

notarize() { # $1: file to submit
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m
}

if [ "$MODE" = release ]; then
  # The app is notarized and stapled first, so it opens even offline once copied out of the .dmg.
  step "Notarizing the app (this takes a few minutes)"
  ditto -c -k --keepParent "$APP" "$OUT/AgentTown-notarize.zip"
  notarize "$OUT/AgentTown-notarize.zip"
  rm "$OUT/AgentTown-notarize.zip"
  xcrun stapler staple "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
fi

# -- Disk image --------------------------------------------------------------------------------
step "Making $DMG"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/AgentTown.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "AgentTown $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"

if [ "$MODE" = release ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  step "Notarizing the disk image"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

# -- Publish -----------------------------------------------------------------------------------
if [ "$PUBLISH" -eq 1 ]; then
  step "Creating a draft GitHub release v$VERSION"
  (cd "$REPO" && gh release create "v$VERSION" "$DMG" --draft --target "$(git rev-parse HEAD)" --title "agent-town $VERSION" \
    --notes "Download AgentTown-$VERSION.dmg, open it, and drag AgentTown into Applications. Requires macOS 15 or later. See the README for the town-link plugin and known issues.")
  echo "Review and publish the draft on GitHub."
fi

step "Done"
echo "App:        $APP"
echo "Disk image: $DMG"
[ "$MODE" = release ] || echo "This is an unsigned test build: on another Mac it is blocked until opened via Privacy & Security."
