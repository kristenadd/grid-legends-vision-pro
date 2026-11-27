# GridLegendsVisionPro

Play your own Mac App Store copy of **GRID Legends** on Apple Vision Pro, on a large virtual screen with a game
controller. The game's own Apple-silicon code runs natively on the headset. There's no streaming and no emulation.

This is built on [VXpro](https://github.com/Ag3497120/VXpro) (included as a submodule in `third_party/VXpro`), which does
the same for Cyberpunk 2077. The plan and phase notes are in [PLAN.md](PLAN.md) and [docs/](docs/).

This is an unofficial fan project, not affiliated with or endorsed by Codemasters, Electronic Arts or Feral
Interactive. GRID Legends and its names are their trademarks. No game files are included: you need your own copy of
the game from the Mac App Store.

## Status

Playable on Apple Vision Pro: menus and full races (tested in November 2026 with an Xbox Wireless Controller).

What works:
- The game in a floating window you can move and resize, at 1280x720 and 60 fps on Feral's Low preset.
- Game controllers through the GameController framework: sticks, triggers and buttons, with rumble on the
  controller's haptics.
- A loading screen in the game's own style (its title screen, "LOADING" in its font) with the title screen's song,
  until the intro video starts.
- The app's name ("GRID Legends") and a layered visionOS icon made from the game's own.

Known limits:
- Higher graphics presets can run out of the app's ~8 GB of memory while a race loads, so the game stays on Low.
- A car's fender can blink briefly. The Mac game does the same on Low settings, so it isn't the port.
- The logging build stutters every second or two. Build with `--quiet` for playing.
- The visionOS simulator only gets as far as the game's window opening (see below).

Not planned for now:
- Stereo 3D. It was tried in November 2026 and set aside because it was uncomfortable to play. Each eye's picture
  was shifted using the game's depth, but the depth didn't always line up with the picture (ghosting on cars), and
  the HUD was shifted along with the scene. The work-in-progress is on the `wip/stereo-3d` branch.
- Head tracking.

## What you need

- An Apple-silicon Mac with Xcode 26 or later (visionOS SDK), XcodeGen, zstd and vgmstream
  (`brew install xcodegen zstd vgmstream`) and Python 3
- Apple Vision Pro in Developer Mode, paired with Xcode, with about 40 GB free
- A **paid** Apple Developer Program team (the app needs Increased Memory Limit and Extended Virtual Addressing)
- GRID Legends from the Mac App Store, installed on the Mac (`/Applications/GRIDLegends.app`)

## Setup

```sh
git clone --recursive <this repository>
cd GridLegendsVisionPro
python3 tools/vxmac_grid.py prepare --team YOUR_TEAM_ID
python3 tools/vxmac_grid.py build --quiet
python3 tools/vxmac_grid.py install
python3 tools/vxmac_grid.py copy
python3 tools/vxmac_grid.py launch
```

After `copy`, open GRID Legends from the headset's home view, or run `launch` from the Mac.

- `build --quiet` is the build for playing: optimised, and it writes no logs, saves no snapshots and checks for no
  frame bursts. For finding problems, a plain `build` adds all of that back: `launch` then starts it and `pull` copies
  the logs to the Mac (`build/grid/logs/`). The logging build stutters every second or two.
- Gamepads rumble on their haptics (`shims/glrumble.m`). The game queues its own HID rumble setup 11.6 days ahead, so
  the shim runs it at once, in memory and only for the exact game build it was read from. `--env GL_RUMBLE=0` turns
  rumble off, `GL_RUMBLE_SCALE` scales it and `GL_RUMBLE_LOG=1` logs the motor levels.
- `copy` sends the game's data (about 34 GB), its Info.plist and **your own App Store receipt, unchanged** into the app's
  container. The game's activation check needs the receipt. Keep the headset awake and charging until `copy` finishes.
  If it stops, run it again and it resumes.
- **Never uninstall the host app** (called "GRID Legends" on the headset). Deleting it deletes the copied game data and
  your saves. To update, keep the same team and bundle ID and run `build` then `install` again.
- The game starts on Feral's Low preset at 1280x720, 60 fps: higher presets can run out of the app's ~8 GB while a
  race loads. `tools/vxmac_grid.py pref --show <text>` / `--set` / `--unset` change Feral's settings on the headset.
- The window shows the game's title screen until its first video, with "LOADING" in the game's own font where
  "PRESS (A)" goes. `build` makes it from the game's own files (`tools/make_loading.swift`), so nothing needs capturing.
  The title screen's own song loops under it and fades out when the video starts. `build` decodes it from the game's
  soundbanks with `vgmstream-cli`; without that tool the splash is silent.
  `build --splash <image>` uses any image instead, with "Loading..." under it (remembered; `--splash title` goes back). The app's icon is made at build time from the game's own (`tools/make_icon.swift`).
- Your game files, the prepared executable, the icon, the splash and the receipt stay on your Mac and headset. Nothing of
  the game goes into git.

## Simulator

`tools/sim_run.sh` builds and runs the host in the visionOS simulator, reading the game's data from the Mac in place. The
simulator's Metal stops the game after its window opens ([docs/PHASE1.md](docs/PHASE1.md)), so it's only for start-up
checks.

## License

The code in this repository is under the [MIT License](LICENSE). VXpro, in `third_party/VXpro`, has its own MIT
License. GRID Legends itself is not covered: it stays the property of its owners.
