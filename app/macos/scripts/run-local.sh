#!/bin/bash
# Builds the app from this checkout and runs it, to try a change before releasing it. Nothing is
# signed, installed or published. Quit it from its menu bar icon (Quit agent-town) or with Ctrl+C.
#
#   app/macos/scripts/run-local.sh                 a demo: fixture 05 (two projects), no sounds
#   app/macos/scripts/run-local.sh --demo 02       another fixture: 01 to 05, or a path to one
#   app/macos/scripts/run-local.sh --live          real Claude Code sessions instead of a demo
#
# Options (any number, in any order):
#   --fake-update   a made-up newer agent-town and town-link (99.0.0), without the network
#   --check-now     a real update check against GitHub (a demo makes no automatic check)
#   --updates       open the Updates window
#   --settings      open the Settings window
#   --compact       compact view (the office at half size), without changing the saved setting
#   --resize WxH    8 seconds in, shrink the window to W by H points, as a drag would (auto-scroll)
#   --breaks        break time after 10 idle seconds instead of 3 minutes (the bench's pastimes)
#   --pastime NAME  with --breaks, standing characters do only NAME: juggle, cube, toss, phone,
#                   chat or doze (seated ones still doze)
#   --sound         play the demo's sounds
#   --zh, --en      run in Traditional Chinese or English
#   --speed N       play the demo N times as fast
#   -- ARGS         pass the rest to the app as is
#
# --live: the installed agent-town and this build would both use the same endpoint file, so the
# installed one is quit first and opened again when this one quits. Sessions already open find
# this build within a few seconds. The demo starts no server, so the installed app keeps working.
#
# This build keeps its own settings, apart from the installed app's (it has no bundle ID).
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)" # app/macos
FIXTURES="$HERE/../../protocol/fixtures"
FIXTURE="05"
LIVE=0
SOUND=NO
ARGS=()

fail() { echo "run-local: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --demo) [ $# -ge 2 ] || fail "--demo needs a fixture"; FIXTURE="$2"; shift ;;
    --live) LIVE=1 ;;
    --fake-update|--check-now|--updates|--settings) ARGS+=("$1") ;;
    --sound) SOUND=YES ;;
    --compact) ARGS+=(-compactView YES) ;;
    --resize) [ $# -ge 2 ] || fail "--resize needs WIDTHxHEIGHT"; ARGS+=(--resize "$2"); shift ;;
    --breaks) ARGS+=(-breakIdleSeconds 10) ;;
    --pastime) [ $# -ge 2 ] || fail "--pastime needs juggle, cube, toss, phone, chat or doze"
      case "$2" in juggle|cube|toss|phone|chat|doze) ;; *) fail "--pastime: juggle, cube, toss, phone, chat or doze" ;; esac
      ARGS+=(-breakIdleSeconds 10 -breakPastime "$2"); shift ;;
    --zh) ARGS+=(-language zh-Hant) ;;
    --en) ARGS+=(-language en) ;;
    --speed) [ $# -ge 2 ] || fail "--speed needs a number"; ARGS+=(--speed "$2"); shift ;;
    --) shift; ARGS+=("$@"); break ;;
    -h|--help) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail "unknown option $1 (see --help)" ;;
  esac
  shift
done

echo "Building…"
(cd "$HERE" && swift build -q)
APP="$HERE/.build/debug/AgentTown"

if [ "$LIVE" = 1 ]; then
  REOPEN=0
  installed() { pgrep -f "AgentTown.app/Contents/MacOS/AgentTown" >/dev/null; }
  if installed; then
    echo "Quitting the installed agent-town; it opens again when this build quits."
    osascript -e 'tell application id "ai.careactive.agenttown-claude-code" to quit' >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do installed || break; sleep 0.25; done
    REOPEN=1
  fi
  reopen() { [ "$REOPEN" = 1 ] && open -b ai.careactive.agenttown-claude-code 2>/dev/null || true; }
  trap reopen EXIT
  echo "Running this build with real sessions. Quit it from its menu bar icon or with Ctrl+C."
  "$APP" -showWindow YES -sound "$SOUND" ${ARGS[@]+"${ARGS[@]}"}
else
  case "$FIXTURE" in
    */*|*.json) FILE="$FIXTURE" ;;
    *) FILE="$(ls "$FIXTURES"/"$FIXTURE"-*.json 2>/dev/null | head -1 || true)" ;;
  esac
  [ -n "$FILE" ] && [ -f "$FILE" ] || fail "no fixture $FIXTURE in protocol/fixtures"
  echo "Running the demo $(basename "$FILE"). Quit it from its menu bar icon or with Ctrl+C."
  "$APP" --demo "$FILE" -showWindow YES -sound "$SOUND" ${ARGS[@]+"${ARGS[@]}"}
fi
