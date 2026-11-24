#!/bin/sh
# sim_run.sh: build GRID Legends Host for the visionOS simulator, install it, point its Documents at the Mac's game
# (Info.plist copied, Resources symlinked: nothing copied, the App Store bundle only read) and launch it.
#   tools/sim_run.sh [SIM_UDID] [-- host arguments]     (default: the first available "Apple Vision Pro" simulator)
# Logs: <container>/Documents/vxmac_host.jsonl and vxmac_program.log (the path is printed).
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
GAME=${GAME:-/Applications/GRIDLegends.app}
BUNDLE_ID=${GRID_BUNDLE_ID:-com.example.GRIDHost}
U=${1:-}
[ "$U" = "--" ] && U=""
[ -n "$U" ] && shift || true
[ "${1:-}" = "--" ] && shift || true
if [ -z "$U" ]; then
    U=$(xcrun simctl list devices available | sed -n 's/.*Apple Vision Pro (\([0-9A-F-]*\)).*/\1/p' | head -1)
fi
[ -n "$U" ] || { echo "no Apple Vision Pro simulator" >&2; exit 1; }

python3 -I "$HERE/tools/grid_prepare.py" --game "$GAME" --platform xrsim > /dev/null
make -s -C "$HERE/shims" sim > /dev/null
(cd "$HERE/app" && xcodegen -q && xcodebuild -project GRIDHost.xcodeproj -scheme GRIDHost \
    -destination 'generic/platform=visionOS Simulator' -derivedDataPath "$HERE/build/dd" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E ' error:|BUILD (SUCCEEDED|FAILED)')

xcrun simctl boot "$U" 2> /dev/null || true
xcrun simctl bootstatus "$U" -b > /dev/null
xcrun simctl terminate "$U" "$BUNDLE_ID" 2> /dev/null || true
xcrun simctl install "$U" "$HERE/build/dd/Build/Products/Debug-xrsimulator/GRIDHost.app"
D=$(xcrun simctl get_app_container "$U" "$BUNDLE_ID" data)
C="$D/Documents/GRIDLegends.app/Contents"
mkdir -p "$C"
cp -f "$GAME/Contents/Info.plist" "$C/Info.plist"
ln -sfn "$GAME/Contents/Resources" "$C/Resources"
# (your own App Store receipt, unchanged, where the Mac bundle has it; GL_NO_RECEIPT=1 leaves it out)
if [ -z "${GL_NO_RECEIPT:-}" ] && [ -f "$GAME/Contents/_MASReceipt/receipt" ]; then
    mkdir -p "$C/_MASReceipt" && cp -f "$GAME/Contents/_MASReceipt/receipt" "$C/_MASReceipt/receipt"
fi
xcrun simctl launch "$U" "$BUNDLE_ID" "$@"
echo "logs: $D/Documents"
