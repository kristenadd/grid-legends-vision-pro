# Phase 3 (2026-11-23): gamepads, and a race

Confirmed on the headset with an Xbox Wireless Controller: d-pad, sticks, A and B work in the menus.

## How

- **Virtual HID pad** (`shims/glhid.m`, in libgliokit). GRID reads controllers through IOHIDManager, which a visionOS app
  cannot use. Every IOHID call the game imports is answered with our own manager, device, element and value objects;
  the real HID system is never called. Each GameController extended gamepad is one device, presented as an
  **Xbox 360 controller** (`045e:028e`): buttons 1-11 in the Mac Xbox 360 driver's order (A B X Y LB RB LS RS
  Start Back Guide), which is what the game uses for this pad. The order of its `inputdevices.json` entry
  (`back:b6 start:b7 ... leftstick:b9`) put Menu on the right-stick click: Start did not pause until the game's controls
  screen showed which button each press became, axes X Y Z Rx Ry Rz (sticks; triggers on Z and Rz) and a hat (d-pad). A timer on
  the game's HID run loop reads the pads every 4 ms and delivers changes through the game's input value callback; the
  game also polls `IOHIDDeviceGetValue`. Pads connecting and disconnecting are matching and removal callbacks.
  `GL_PAD_VID`/`GL_PAD_PID` present another entry of the database.
- **The window must claim controller input.** By default visionOS turns a controller's buttons into pinches on the
  view you look at; A and B never reached GameController in the floating window (the d-pad did). Two changes:
  - `GCSupportsControllerUserInteraction` off in GRID's Info.plist (VXpro's copy unchanged);
  - a `GCEventInteraction` (gamepad events) on the window's game view (`grid_profile.m`), as Apple's documentation
    asks of a Metal game.

## How the game reads the pad (first run's log)

`IOHIDManagerCreate` → `SetDeviceMatchingMultiple` → matching / removal / input value callbacks →
`ScheduleWithRunLoop` → `Open` → `CopyDevices`; per device `GetProperty`, `CopyMatchingElements`; then
`IOHIDDeviceGetValue` polling. No raw input reports for this device type.

## Diagnostics

- `GL_PAD_LOG=1`: the pad's button and hat changes as GameController reports them.
- `GL_PAD_TEST=<usage>@<seconds>`: the pad presses that HID button by itself (used to prove the game's mapping:
  button 1 on the title screen opened "Create new save game", as A does).

## A race: memory

The first race attempt was killed by visionOS at the app's memory limit (no crash report; the log ended at 7.36 GB with
835 MB left while the race loaded). In the menus the game already uses ~6.1 GB (Mac: ~5 GB):
- ~2.9 GB of the game's own data before any race;
- **36,773 Metal render pipelines** created in one go at start-up (~1.7 GB), whatever the binary archives
  (`VXMAC_BINARY_ARCHIVES=0`) or the reported RAM (`VXMAC_MEMSIZE_MB=8192`) - neither changed anything;
- graphics ~3 GB.

Feral's **Low** preset at **1280x720** fits: a race ran steady at ~6.9 GB with ~1.3 GB left, ~30 fps (the game's
`FramerateLimit` 30). New installs are seeded with it (`grid_profile.m`: GraphicsSettings all low,
`ShouldLoadDefaultPreset` 0, `Setup\Apple M2 GPU\ScreenW/H` 1280x720); a fresh launch kept `DefaultPreset = low`.
Higher settings in the game's options may run out of memory again.

### Memory and frame rate follow-up (same day)

Feral's Metal-layer settings live in `HKCU\Software\IndirectX\Direct3D\Config` (names from the game's
`F3DConfig::KeyAccessor<...>::kKeySuffix` symbols; `tools/vxmac_grid.py pref` shows, sets and unsets them with the
game stopped). Measured at the title screen, 1280x720 Low:

| Setting | Pipelines | Title-screen footprint |
|---|---|---|
| defaults | 36,773 | 6.1-6.2 GB and growing |
| `EnableF3DWarmer` 0 (the pipeline warmer) | 36,773 | no change (reverted) |
| **`HarvestBinaryArchive` 0** (no growing pipeline archive) | 36,773 | **5.38 GB, steady** |

The 36,773 pipelines are the game's own loading (also with empty binary archives or 8 GB reported RAM); VXpro's
pipeline hooks only ask Metal for reflection in their dump mode (off). A race needs ~7.0 GB either way (peak 7.03 GB,
~1.2 GB left): harvesting off removes the slow growth, not the race's need.

**Frame rate:** the game's own limit was 30 (`GraphicsSettings\FramerateLimit`). At 60 a race ran at a median
59.2 fps (52.5-67), GPU ~62 % busy, thermal state 2 (serious); memory unchanged.

New installs are seeded with both (`FramerateLimit` 60, `HarvestBinaryArchive` 0); a fresh simulator launch kept them.

The headset reached thermal state 3 (critical) after hours of testing, during the race.

## Not done

- Rumble: `IOHIDDeviceSetReport`/`SetValue` are accepted and ignored.
- Racing wheels (no USB on the headset).
- Driving feel with the pad (stick dead zones, trigger travel) not tuned.

## Open: textures blinking about once a second (reported 2026-11-23)

A texture on the car, and some others in races, blink on and off roughly every second. Checked offline:
- VXpro's render-pass hook only rewrites passes for its immersive HUD (off in the window); its encoder "clears" are its
  own bookkeeping. Not the cause.
- The game manages graphics memory itself: it reads `recommendedMaxWorkingSetSize` (VXpro answers 4096 MB; a race used
  ~3.6 GB), `currentAllocatedSize`, and marks resources purgeable (`setPurgeableState:`); Feral's settings include
  texture/buffer paging (`EnableTexturePaging`, `TexturePageOutTime`, `ResourcePagingBudget/Target`).
- In a race the system was compressing ~2.4 GB of the app's memory: heavy memory pressure, under which the system may
  discard *volatile* resources. A Mac with plenty of RAM rarely does.

First hypothesis: cached textures marked volatile are discarded by the system and reloaded by the game. libglmtl logs
the purgeable calls by state every 5 s (`GL_NO_VOLATILE=1` keeps them non-volatile). **Ruled out on the headset
(2026-11-24):** in a race with the left front fender visibly blinking (about half a second, about once a second) the
game made no `setPurgeableState:` calls at all.

Frame bursts (`tools/vxmac_grid.py burst`, app/Sources/grid_burst.m: the game's presented frames read back at full size;
devicectl has no screenshots or screen recording on visionOS): two 4 s bursts of every second frame, the second while
the fender was blinking, show no region that changes and changes back (window 1 and 6 frames, 32 px cells). So either
it alternates frame to frame (every second frame always sees the same state), or it isn't in the game's picture and
comes from the window's display path. Next: a burst of every frame (`burst --step 1 --frames 120`; the build that takes
the step from the request is built, not yet installed). Then Feral's texture paging (`EnableTexturePaging=0`) and the
4096 MB budget (`VXMAC_GPU_WORKING_SET_MB`) if it is in the game's frames.

Note: since `VXMAC_GPU_FAMILY_MAC=1` became the default the game takes its Mac path with shared heaps, which the
simulator refuses (`MTLStorageModePrivate is required for heaps`): the simulator now stops before the game's window.
