# Phase 2 (2026-11-23): GRID Legends' title screen on Apple Vision Pro, in a floating window

Headset: Apple Vision Pro (M2), visionOS 27.2.1, Developer Mode. Signed with a paid team (Increased Memory Limit,
Extended Virtual Addressing checked in the signed app by `tools/vxmac_grid.py build`).

## Setup

`tools/vxmac_grid.py prepare --team <TEAM> / build / install / copy / launch / pull` (see the README).
`copy` sent 74 items: the game's Info.plist, your unchanged receipt, Resources (118,536 files, 36.0 GB), then checked
every file's size on the headset: 0 mismatches. It took about an hour over the network.

## Fixed on the headset

| Run | What happened | Fix |
|---|---|---|
| 1, 2 | SIGSEGV within 1 s in `IONotificationPortGetRunLoopSource(NULL)`: a game thread watches USB devices and system power; the app sandbox refuses the IOKit notification port and the game does not check | **libgliokit**: a refused port or power source becomes a quiet stand-in (no devices, no power events). The simulator didn't show this (it uses the Mac's IOKit) |
| 3 | 22 s: 16 GB reservation OK, window, audio (Wwise through VXpro's HAL stand-in) and the first frames; then SIGSEGV in WebCore: `CFeralNSWebView` (Feral's legacy `WebView` subclass) created from the game thread | **libglwebkit**: the legacy WebView family as inert stand-ins (WKWebView untouched). Legacy pages do not show |
| 4 | **Title screen, steady** (immersive screen) | |
| 5 | Floating window by default (you asked): sound, but a black window. VXpro looks for the game's CAMetalLayer only on the window's content view; Feral's is on a child view | `grid_metal_layer` (grid_profile.m, host hook 5): the window's views and layers searched; the layer moved into the window and kept at the window's size |
| 7 | (my bug) the search called `+sharedApplication` before the game made its `CFeralNSApplication`, so the game ran with a plain NSApplication | read libvxkit's `NSApp` only |
| 9 | SIGTRAP in the Bluetooth HAL plug-in's start, reached from the game's `AudioObjectHasProperty` (VXpro answers three HAL calls without the HAL; GRID uses three more) | **libglca**: HasProperty and the property listeners answered without the HAL too |
| video | Intro videos: right brightness, scrambled colour (green and purple bands, stripes). Feral picks its video format path from Metal's `supportsFamily:` answers; on visionOS the M2 says no to Mac2 (2002), on the Mac yes | `VXMAC_GPU_FAMILY_MAC=1` (VXpro's switch) by default in grid_profile.m: Mac1/Mac2 answered yes. Confirmed on the headset |
| 10 | **Title screen in the floating window**, confirmed on the headset; ~28 fps presented, 5.3 GB, no HAL plug-ins loaded | |

Run 1's "app went to the background" was this crash, not the headset being off.

## Run 4 (90 s, title screen)

- Game 30.2 fps (33.4 ms frames), compositor 90.6 Hz, both eyes warped (181/s, 2.24 ms GPU), presenter in `screen` mode
  (the immersive space). Since run 5 the default is a floating window instead (`-present flat`);
  `tools/vxmac_grid.py launch --present immersive` brings the immersive screen back.
- Footprint 3.76 GB, 4.4 GB still available to the app.
- Feral's activation passed with your receipt; pre-game launcher skipped by the seeded settings.

(The headset's frame snapshot is pulled to `build/grid/logs/<tag>/snap.png`; game artwork stays out of git.)

## Not done / next

- **Gamepads (Phase 3):** the game reads controllers through IOHIDManager, which the app cannot use; a virtual HID
  pad fed by GameController is next. Until then only the host's keyboard and mouse path reaches the game.
- Legacy-WebView pages (which ones is not known yet) do not show.
- In-race memory and frame rate not measured.
