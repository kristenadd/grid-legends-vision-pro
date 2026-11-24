#!/bin/sh
# mac_trial.sh: Phase 0 Mac test. Converts the game's executable to a dylib (VXpro's macho_prepare.py, macOS
# platform) and runs it from a stand-in app bundle with another bundle id and no App Store receipt, the way the
# visionOS host will run it. The installed game is only read; its Resources folder is symlinked, not copied.
#   tools/mac_trial.sh [OUT_DIR] [-n]        (-n: load and run initializers only, do not start the game)
# Env: GAME (default /Applications/GRIDLegends.app), VXPRO (default ../VXpro next to this repository).
# The test copy keeps its own settings in ~/Library/Application Support/Feral Interactive/GRIDLegends
# (the App Store game uses its sandbox container, so its saves are untouched).
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
GAME=${GAME:-/Applications/GRIDLegends.app}
VXPRO=${VXPRO:-$HERE/../VXpro}
OUT=${1:-$HERE/build/mac_trial}
NOLAUNCH=${2:-}
[ -x "$GAME/Contents/MacOS/GRIDLegends" ] || { echo "game not found: $GAME" >&2; exit 1; }
[ -f "$VXPRO/tools/macho_prepare.py" ] || { echo "VXpro not found: $VXPRO" >&2; exit 1; }

mkdir -p "$OUT"
lipo -thin arm64 "$GAME/Contents/MacOS/GRIDLegends" -output "$OUT/GRIDLegends.thin"
python3 -I "$VXPRO/tools/macho_prepare.py" "$OUT/GRIDLegends.thin" "$OUT/GRIDLegends.dylib" --platform macos \
    --as-dylib @rpath/GRIDLegends.dylib --json "$OUT/GRIDLegends.json" > /dev/null
ENTRY=$(python3 -I -c "import json,sys; print([c for c in json.load(open(sys.argv[1]))['changes'] if c['cmd']=='as_dylib'][0]['entry_offset'])" "$OUT/GRIDLegends.json")
xcrun clang -O1 "$VXPRO/tests/dyhost_mac.c" -o "$OUT/dyhost_mac"

APP="$OUT/GRIDTest.app/Contents"
mkdir -p "$APP/MacOS" "$APP/Frameworks"
cp "$OUT/dyhost_mac" "$APP/MacOS/"
cp "$OUT/GRIDLegends.dylib" "$APP/Frameworks/"
ln -sfn "$GAME/Contents/Resources" "$APP/Resources"
cp "$GAME/Contents/Info.plist" "$APP/Info.plist"
plutil -replace CFBundleExecutable -string dyhost_mac "$APP/Info.plist"
plutil -replace CFBundleIdentifier -string com.example.gridtest "$APP/Info.plist"
codesign -s - -f "$APP/Frameworks/GRIDLegends.dylib" "$APP/MacOS/dyhost_mac" 2> /dev/null

echo "entry_offset $ENTRY"
if [ "$NOLAUNCH" = "-n" ]; then
    exec "$APP/MacOS/dyhost_mac" "$APP/Frameworks/GRIDLegends.dylib" "$ENTRY" -n
fi
exec "$APP/MacOS/dyhost_mac" "$APP/Frameworks/GRIDLegends.dylib" "$ENTRY"
