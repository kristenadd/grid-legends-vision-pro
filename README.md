# GridLegendsVisionPro

Play your own Mac App Store copy of **GRID Legends** on Apple Vision Pro, on a large virtual screen with a game
controller. The game's own Apple-silicon code runs natively on the headset. There's no streaming and no emulation.

This is built on [VXpro](https://github.com/Ag3497120/VXpro) (included as a submodule in `third_party/VXpro`), which does
the same for Cyberpunk 2077. Work in progress: see [PLAN.md](PLAN.md) and the phase notes in [docs/](docs/).

## What you need

- An Apple-silicon Mac with Xcode 26 or later (visionOS SDK), XcodeGen (`brew install xcodegen`) and Python 3
- Apple Vision Pro in Developer Mode, paired with Xcode, with about 40 GB free
- A **paid** Apple Developer Program team (the app needs Increased Memory Limit and Extended Virtual Addressing)
- GRID Legends from the Mac App Store, installed on the Mac (`/Applications/GRIDLegends.app`)

## Setup

```sh
git clone --recursive <this repository>
cd GridLegendsVisionPro
python3 tools/vxmac_grid.py prepare --team YOUR_TEAM_ID
python3 tools/vxmac_grid.py build
python3 tools/vxmac_grid.py install
python3 tools/vxmac_grid.py copy
python3 tools/vxmac_grid.py launch
python3 tools/vxmac_grid.py pull
```

The last command copies the logs back to the Mac (`build/grid/logs/`).

- `copy` sends the game's data (about 34 GB), its Info.plist and **your own App Store receipt, unchanged** into the app's
  container. The game's activation check needs the receipt. Keep the headset awake and charging until `copy` finishes.
  If it stops, run it again and it resumes.
- **Never uninstall the host app** (called "GRID Legends" on the headset). Deleting it deletes the copied game data and
  your saves. To update, keep the same team and bundle ID and run `build` then `install` again.
- The game starts on Feral's Low preset at 1280x720, 60 fps: higher presets can run out of the app's ~8 GB while a
  race loads. `tools/vxmac_grid.py pref --show <text>` / `--set` / `--unset` change Feral's settings on the headset.
- The window shows a splash until the game's first video (the choice is remembered): `build --loading <capture>` makes
  it from a capture of the title screen (`burst --step 1 --frames 1`), with "LOADING" in the game's own font where
  "PRESS (A)" was (`tools/make_loading.swift`); `build --splash <image>` uses any image with "Loading..." under it. The app's icon is made at build time from the game's own (`tools/make_icon.swift`).
- Your game files, the prepared executable, the icon, the splash and the receipt stay on your Mac and headset. Nothing of
  the game goes into git.

## Simulator

`tools/sim_run.sh` builds and runs the host in the visionOS simulator, reading the game's data from the Mac in place. The
simulator's Metal stops the game after its window opens ([docs/PHASE1.md](docs/PHASE1.md)), so it's only for start-up
checks.

## Licence

This repository's code: see VXpro's MIT licence for the parts derived from it. Not affiliated with Codemasters, Electronic
Arts or Feral Interactive.
