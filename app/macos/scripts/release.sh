#!/bin/bash
# Builds AgentTown.app and AgentTown-<version>.dmg, signed with a Developer ID and notarized by
# Apple, so it opens on any Mac (macOS 15 or later) without Xcode and without "Open Anyway".
#
#   app/macos/scripts/release.sh             build, sign, notarize, make the .dmg
#   app/macos/scripts/release.sh --publish   the same, then publish GitHub release v<version> and
#                                            push the Homebrew cask, so 'brew upgrade' sees it
#   app/macos/scripts/release.sh --publish --draft
#                                            a draft release instead, to review on GitHub first;
#                                            the cask is updated but not committed
#   app/macos/scripts/release.sh --unsigned  a test build: no Developer ID, no notarization
#   app/macos/scripts/release.sh --unsigned --publish
#                                            an unsigned pre-release on GitHub
#
# --publish writes the new version and the .dmg's checksum into Casks/agent-town.rb (the Homebrew
# cask; this repo is the tap). Once the release is published and its .dmg's checksum matches,
# it commits that change and pushes it, from the main branch only. Homebrew reads the cask from
# the repo, not from Releases: without the push, 'brew upgrade' keeps the old version.
#
# One-time setup on the Mac that releases (no secrets are ever stored in the repo):
#   1. A Developer ID Application certificate (with its private key) in the login keychain,
#      made through the developer website; see docs/releasing.md, Part A.
#   2. An app-specific password from account.apple.com, saved in the keychain with:
#      xcrun notarytool store-credentials agent-town-notary --apple-id <email> --team-id <TEAM ID>
#
# Settings (environment):
#   VERSION         default: the macOS app's version (AppInfo.fallbackVersion in Sources/AgentTown/About.swift)
#   BUNDLE_ID       default: ai.careactive.agenttown
#   SIGN_IDENTITY   default: the one "Developer ID Application" certificate in the keychain
#   NOTARY_PROFILE  default: agent-town-notary
#   ARCHS           default: "arm64 x86_64" (a universal app)
set -euo pipefail

MODE=release
PUBLISH=0
DRAFT=0
for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=1 ;;
    --draft) DRAFT=1 ;;
    --unsigned) MODE=unsigned ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

PKG="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$PKG/../.." && pwd)"
OUT="$PKG/build/release"
APP="$OUT/AgentTown.app"

VERSION="${VERSION:-$(sed -nE 's/.*static let fallbackVersion = "([^"]+)".*/\1/p' "$REPO/app/macos/Sources/AgentTown/About.swift")}"
[[ -n "$VERSION" ]] || { echo "release.sh: no version found in About.swift (AppInfo.fallbackVersion)" >&2; exit 1; }
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
[ "$DRAFT" -eq 0 ] || [ "$PUBLISH" -eq 1 ] || fail "--draft goes with --publish"
if [ "$PUBLISH" -eq 1 ]; then
  [ -z "$(git -C "$REPO" status --porcelain)" ] || fail "commit your changes before publishing"
  command -v gh >/dev/null || fail "--publish needs the GitHub CLI (gh)"
  if [ "$DRAFT" -eq 0 ]; then
    [ "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)" = main ] || fail "publish from the main branch (or add --draft)"
    git -C "$REPO" fetch -q origin main
    [ "$(git -C "$REPO" rev-parse HEAD)" = "$(git -C "$REPO" rev-parse origin/main)" ] \
      || fail "main is not the same as origin/main: push or pull first"
  fi
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
# The app icon (Finder, the Apps launcher, About), every size made from the 1024 px master.
ICON_SRC="$REPO/assets/icons/app-icon-1024.png"
[ -f "$ICON_SRC" ] || fail "no app icon at $ICON_SRC"
ICONSET="$OUT/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -s format png -z $s $s "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -s format png -z $((s * 2)) $((s * 2)) "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>AgentTown</string>
  <key>CFBundleDisplayName</key><string>agent-town</string>
  <key>CFBundleExecutable</key><string>AgentTown</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
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
  <key>NSHumanReadableCopyright</key><string>© $(date +%Y) Samson Chen</string>
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
  if [ "$DRAFT" -eq 1 ]; then
    flags=(--draft)
  elif [ "$MODE" = release ]; then
    flags=(--latest)
  else
    flags=(--prerelease)
  fi
  if [ "$MODE" = release ]; then
    notes="Download AgentTown-$VERSION.dmg, open it, and drag AgentTown into Applications, or install with Homebrew (see the README). Requires macOS 15 or later."
  else
    notes="Unsigned pre-release: macOS blocks the app the first time it opens. Open System Settings → Privacy & Security and click Open Anyway. Install with Homebrew or download AgentTown-$VERSION.dmg; see the README. Requires macOS 15 or later."
  fi
  step "Creating GitHub release v$VERSION (${flags[*]})"
  (cd "$REPO" && gh release create "v$VERSION" "$DMG" "${flags[@]}" --target "$(git rev-parse HEAD)" \
    --title "agent-town for macOS $VERSION" --notes "$notes")

  CASK="$REPO/Casks/agent-town.rb"
  SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
  sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
  if [ "$DRAFT" -eq 1 ]; then
    echo "Updated $CASK to $VERSION ($SHA), not committed."
    echo "Review and publish the draft on GitHub, then commit and push the cask: 'brew upgrade' sees the release only then."
  else
    step "Checking the uploaded disk image"
    check="$(mktemp -d)"
    (cd "$REPO" && gh release download "v$VERSION" --pattern "AgentTown-$VERSION.dmg" --dir "$check")
    got="$(shasum -a 256 "$check/AgentTown-$VERSION.dmg" | cut -d' ' -f1)"
    rm -rf "$check"
    [ "$got" = "$SHA" ] || fail "the uploaded .dmg's checksum ($got) is not the local one ($SHA); the cask is updated but not committed"
    step "Pushing the Homebrew cask"
    git -C "$REPO" commit -q -m "Cask: agent-town $VERSION" -- Casks/agent-town.rb
    git -C "$REPO" push -q origin main
    echo "Released $VERSION. Users get it with: brew update && brew upgrade --cask agent-town"
  fi
fi

step "Done"
echo "App:        $APP"
echo "Disk image: $DMG"
[ "$MODE" = release ] || echo "This is an unsigned test build: on another Mac it is blocked until opened via Privacy & Security."
