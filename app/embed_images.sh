#!/bin/sh
# Xcode build phase of GRID Legends Host: the shims (../build/xros, simulator ../build/xrsim; ../shims/Makefile) and
# the game's prepared executable (GRID_IMAGES, default ../build/prepared/Frameworks, simulator ../build/prepared_sim/
# Frameworks; tools/grid_prepare.py) into the app's Frameworks, each signed with the build's identity, and the image's
# GRIDLegends.vxmac.plist (its entry point) into Resources. The prepared image is a local copy of your own game, never
# in git.
set -e
if [ "$PLATFORM_NAME" = xrsimulator ]; then
  make -C "$SRCROOT/../shims" sim
  SHIMS="$SRCROOT/../build/xrsim"; IMAGES="${GRID_IMAGES:-$SRCROOT/../build/prepared_sim/Frameworks}"
else
  make -C "$SRCROOT/../shims"
  SHIMS="$SRCROOT/../build/xros"; IMAGES="${GRID_IMAGES:-$SRCROOT/../build/prepared/Frameworks}"
fi
FW="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
RES="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
mkdir -p "$FW" "$RES"
SIGN="${EXPANDED_CODE_SIGN_IDENTITY:--}"
for f in "$SHIMS"/*.dylib; do
  cp -f "$f" "$FW/"
  codesign --force --sign "$SIGN" --timestamp=none "$FW/$(basename "$f")"
done
if [ -f "$IMAGES/GRIDLegends.dylib" ]; then
  if [ ! -f "$FW/GRIDLegends.dylib" ] || [ "$IMAGES/GRIDLegends.dylib" -nt "$FW/GRIDLegends.dylib" ]; then
    cp -f "$IMAGES/GRIDLegends.dylib" "$FW/GRIDLegends.dylib"
  fi
  codesign --force --sign "$SIGN" --timestamp=none "$FW/GRIDLegends.dylib"
  cp -f "$IMAGES/GRIDLegends.vxmac.plist" "$RES/"
else
  echo "embed_images: warning: no $IMAGES/GRIDLegends.dylib (run tools/grid_prepare.py); the app will run VXpro's test program if embedded, else nothing"
fi
