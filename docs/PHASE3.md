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

Next lever if more headroom is needed: the start-up pipeline load (Feral's "F3D Warmer", settings under
`Software\IndirectX\Direct3D\Config`), not explored yet.

The headset reached thermal state 3 (critical) after hours of testing, during the race.

## Not done

- Rumble: `IOHIDDeviceSetReport`/`SetValue` are accepted and ignored.
- Racing wheels (no USB on the headset).
- Driving feel with the pad (stick dead zones, trigger travel) not tuned.
