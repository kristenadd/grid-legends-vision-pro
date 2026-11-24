# GRID Legends on Apple Vision Pro — porting plan

**Scope (decided 2026-11-23): play the game on a large virtual screen with a GameController-framework
gamepad (Xbox, PlayStation, MFi). No stereo 3D or head-tracked camera for now.**

Goal: run your own Mac App Store copy of GRID Legends natively on Apple Vision Pro, the way
[VXpro](../VXpro) runs Cyberpunk 2077: the game's arm64 Mach-O is converted to a dylib, its macOS-only
libraries are replaced by shims, it runs inside a visionOS host app, and its Metal frames go to an
immersive presenter. No emulation, no streaming.

Written 2026-11-23 from a read of VXpro (`docs/DESIGN.md`, `tools/`, `shims/`, `app/`, `vr/`) and a
read-only inspection of `/Applications/GRIDLegends.app`.

## 1. What the game looks like (findings)

| | GRID Legends (Mac App Store) | Cyberpunk 2077 (VXpro) | Impact |
|---|---|---|---|
| Port by | Feral Interactive (`com.feralinteractive.gridlegends`, RC9, build 376070) | CDPR | Different engine wrapper; nothing in VXpro is GRID-specific |
| Executable | 1 thin arm64 image (48 MB), macOS 13.3 SDK, `LC_MAIN` entry 0xFFC0 | 4 images, 150 MB | Simpler: one image to prepare |
| Encryption | No `LC_ENCRYPTION_INFO` | None | Conversion is possible |
| Bundled frameworks | `QuincyKit.framework` (crash reporter, AppKit; **not linked** by the game) | Bink, Galaxy, GameServices | Leave it out |
| Data | `Contents/Resources/Data`: 34 GB (`data_win` 23 GB, `data` 10 GB, `MetalArchives` 418 MB) | 80–160 GB | Fits easily on the headset |
| Data lookup | Feral VFS (`vfs-config.xml`, `${DozeAppInstall}`), from `Contents/Resources/Data/` under the bundle | `_NSGetExecutablePath` | Needs a bundle-path redirect for the game image, not the exec-path trick |
| App entry | `NSApplicationMain`, principal class `CFeralNSApplication`, `MainMenu.nib` (menu only) | Custom loop | libvxkit needs `NSApplicationMain` |
| Gamepads | **Raw IOHIDManager** (`CGPHIDDevice_*` classes for Xbox/PS/Logitech/Fanatec/Thrustmaster); GameController is used only for `GCKeyboard`/`GCMouse` | GameController | **Main new work item** (see 3.3) |
| Force feedback | ForceFeedback.framework (12 calls) | — | Stub |
| Audio | Wwise over CoreAudio/AudioUnit (`AudioObject*` HAL calls); OpenAL (40 calls incl. capture, probably voice chat) | Wwise-like path, VXpro's `vxaudio.m` | Reuse VXpro's HAL work; new OpenAL shim |
| Upscalers | MetalFX spatial + temporal (both descriptors imported) | MetalFX temporal | VXpro's libvxmtlfx capture should work as is |
| Store / online | StoreKit (IAP, review), CloudKit, receipt reading (`appStoreReceiptURL` + PKCS7 OIDs) | Game Center / Galaxy | **Gate** (see Phase 0) |

### Trial conversion (done, scratchpad only, nothing in this repo)

VXpro's tooling already handles the binary:

- `lipo -thin arm64` then `macho_prepare.py --system-shim --as-dylib @rpath/GRIDLegends.dylib` succeeded:
  platform → visionOS 26, `__PAGEZERO`/`LC_MAIN`/`LC_LOAD_DYLINKER` removed, entry_offset 65472.
- VXpro's shims built for visionOS as they are, and `check_imports.py` against them reports
  **133 non-weak + 24 weak missing symbols**. That is the whole link-time gap:

| Library | Missing | Plan |
|---|---|---|
| OpenAL (whole framework absent) | 40 | `libvxopenal`: stubs that report "no device" first; later OpenAL Soft (LGPL) or AVAudioEngine if the game needs it for more than chat |
| AppKit → libvxkit | 31 | add `NSApplicationMain`, `NSAlert`, `NSOpenPanel`/`NSSavePanel`, `NSMenuItem`, `NSImageView`, `NSGraphicsContext`, `NSPasteboard`, Touch Bar classes (inert), a few notification names |
| Carbon → libvxcarbon (empty today) | 16 | TIS keyboard-layout calls (US layout), `ReceiveNextEvent` etc. returning "no event", `SetSystemUIMode` no-op |
| ForceFeedback (absent) | 12 | `libvxff`: report no FF devices; later map rumble to GCController haptics |
| CoreServices | 11 | `Gestalt`, `LSCopyApplicationURLsForBundleIdentifier`, `LSOpenCFURLRef`, `UCKeyTranslate`, two date helpers, five libm re-exports |
| CoreGraphics → libvxcg (weak) | 21 | `CGEvent*` (inert), display reconfiguration callbacks, gamma tables, `CGDirectDisplayCopyCurrentMetalDevice`, window-list calls |
| Security → libvxsec | 8 | legacy keychain calls → `errSecUnimplemented` (or map to the visionOS keychain if saves/login need it) |
| CoreVideo | 6 | `CVDisplayLink*` → timer/CADisplayLink stand-in (like VXpro's `CAMetalDisplayLink` stand-in) |
| Collaboration (absent) | 2 | `CBIdentity` stub returning nil |
| Metal → libvxmtl (weak) | 3 | three device notification names |
| Foundation / AVFoundation | 2 | `NSUserNotificationCenter`, `AVCaptureScreenInput` stub classes |
| ApplicationServices, ScriptingBridge | 0 symbols | empty shims so dyld can load the image |

`macho_prepare.py` also needs mapping entries for those five absent frameworks (it currently rewrites them
to flat `/System/Library/Frameworks/X.framework/X` paths that do not exist on visionOS).

Link-time completeness does not mean the game runs: anything it reaches through
`NSClassFromString`/`objc_msgSend`/`dlsym` shows up only at run time (libvxkit's catch-all logs it).

## 2. Repository approach

Do not fork VXpro wholesale. Most of it is Cyberpunk-specific (pool patch, VRIK/hand weapons, NPU
interpolation, CDPR cloud, weapon catalogs). Take the game-independent core:

- `tools/macho_prepare.py`, `tools/check_imports.py`, `tools/data_manifest.py` (pool patch made optional, keyed per game)
- `shims/` (all of it, plus the new ones above)
- `vr/` presenter: `xros_vr.m`, `warp_core.*`, `frame_pipeline.*`, `vxmac_vr_glue.m`
- `app/` host: `VXMacApp.swift`, `VXMacImmersive.swift`, `host.m`, `project.yml`, `embed_images.sh`, entitlements
- `testapp/vxmac_test.m` and `tests/dyhost_mac.c` (the Mac-side harness)

Recommended layout here: VXpro as a **git submodule pinned to `4498bec`** (MIT, keep its notices) for
the shared core, and this repo holding only GRID-specific code (`shims/` additions, `tools/vxmac_grid.py`,
the game profile, docs). If the shared core needs changes, prefer sending them upstream to VXpro so
both games keep one shim layer. Fall back to a vendored copy only if upstream changes become a burden.

Proposed tree:

```
GridLegendsVisionPro/
  third_party/VXpro/          submodule (shims, vr, host, tools)
  shims/                      libvxopenal, libvxff, libvxcollab, libvxappsvc, libvxsbridge, libvxcoreservices,
                              libvxcarbon additions, virtual HID gamepad (vxhid.m)
  app/                        host project (project.yml pulls sources from third_party/VXpro)
  tools/vxmac_grid.py         doctor / prepare / build / install / copy / launch / pull
  docs/DESIGN.md, docs/SETUP.md
  build/                      git-ignored work copies (never commit game files)
```

## 3. Phases

### Phase 0 — Feasibility gates (Mac only) — **done 2026-11-23: go** ([results](docs/PHASE0.md))

Loads as a dylib; runs to the title screen with no receipt and another bundle id; no pool patch needed
so far. New item for Phase 1: skip Feral's pre-game launcher (`GameOptionsDialogShouldShow = 0`).
In-race memory is still to be measured.

1. **Receipt / licence behaviour.** The binary reads `appStoreReceiptURL` and carries PKCS7 receipt OIDs.
   Find out (static: who calls `appStoreReceiptURL` and what happens on failure; dynamic: run a re-signed
   copy on the Mac via `dyhost_mac`) whether the game exits, nags, or carries on when the receipt does not
   validate outside its original bundle. **If it refuses to run, stop and decide.** This plan does not
   include patching out licence checks.
2. **Memory reservations.** Run the game on the Mac and check `vmmap`/VXpro's reservation logging for
   large fixed reservations (Cyberpunk needed a pool patch because a 64 GB reservation failed on the
   headset). GRID's Mac minimum spec is 8 GB, so this may not be needed.
3. **Mac-side harness.** Convert with `--platform macos` and load it from `dyhost_mac -n` to prove the
   dylib conversion, fixups and C++ initializers work before touching the headset.

### Phase 1 — Link and load (~1 week)

- Write the shims in the table above; extend `macho_prepare.py`'s library map.
- `check_imports.py` → **non-weak missing: 0**.
- libvxkit: `NSApplicationMain(argc, argv)` = read `NSPrincipalClass`, `[cls sharedApplication]`, skip
  `MainMenu.nib` (it only holds the menu), `-run`.
- Bundle redirect: the game builds `Contents/Resources/Data/` from its bundle path. Give the game image
  a fake `NSBundle mainBundle`/`CFBundleGetMainBundle` rooted at `Documents/GRIDLegends.app` (resources,
  Info.plist, bundle id), scoped to calls from the game image, as VXpro does with `VXMAC_EXECUTABLE_PATH`.
- Host app: rename VX Mac Host to a GRID host; game profile (env defaults) instead of the Cyberpunk one.
- Simulator first (`make sim`, `--platform xrsim`) with the data symlinked, as VXpro did, to get through
  startup; expect it to stop at the simulator's Metal heap limits.

### Phase 2 — First frames on the headset, flat panel (~1–2 weeks)

- `tools/vxmac_grid.py copy`: push `Contents/Resources/Data` (34 GB) into the app container with
  `devicectl device copy to`, one file/folder per call, resumable. Watch for case sensitivity: Feral's
  VFS lowercases some paths, the headset's file system is case-sensitive.
- `MetalArchives` were compiled for Mac GPUs; try with them and with `VXMAC_BINARY_ARCHIVES=0`.
- Present in the presenter's world-locked panel mode (VXpro mode (b)). Target: menus, a race, stable
  memory under the ~8 GB limit with the Increased Memory Limit entitlement.
- Keyboard/mouse via GameController → libvxkit events works already (VXpro).

### Phase 3 — Gamepads (~1–2 weeks, the biggest new piece)

Target: any controller visionOS pairs over Bluetooth and exposes through GameController
(`GCController.extendedGamepad`): Xbox Wireless, DualSense/DualShock 4, MFi pads.


Feral talks to gamepads through IOHIDManager, which a visionOS app cannot use for Bluetooth pads.
Build a **virtual HID layer** in libvxiokit: `IOHIDManagerCopyDevices`/matching callbacks return a
synthetic device that looks like an Xbox Wireless Controller (vendor/product IDs, usage page/usage,
elements with logical min/max, input value callbacks, `IOHIDDeviceGetValue`), fed from `GCController`
(extended gamepad) on the host. Then the game's own Xbox action map and button icons apply.
DualSense as a second profile. Rumble: `ForceFeedback`/`IOHIDDeviceSetReport` output → `GCDeviceHaptics`.
Wheels are out of scope (no USB HID on the headset).

### Phase 4 — Audio (~3–5 days)

Wwise's Mac backend uses the CoreAudio HAL (`AudioObject*`), which visionOS does not offer for output.
Reuse VXpro's `shims/vxaudio.m` (its HAL stand-in over RemoteIO; note VXpro turned its HAL path off by
default after a long-session memory leak, h67 — check which path suits GRID). OpenAL: stubs first; only
build OpenAL Soft if something besides voice chat needs it.

### Phase 5 — The virtual screen

Only VXpro's world-locked panel mode (its mode (b)) is used: the game's frame drawn on a large flat
screen placed in front of you, re-placed when you recenter. Pin the presenter to it (`VXRT_VR_MODE=screen`
or the equivalent in the GRID game profile) so its automatic switch to head-driven VR never engages; none
of VXpro's depth/camera hooks, NPU interpolation or hand tracking are built in. Options worth adding:
screen size/distance, a dim or dark surround, recenter on a controller button chord. Game render
resolution 1920x1080 (or 1600x900) at 16:9.

### Phase 6 — Performance and settings

Frame pacing (the in-flight bound from VXpro's fix for corrupted skinned meshes), MetalFX spatial or
temporal if the game's own upscaling helps, and a recommended low/medium preset in the game's preferences
(Feral stores them under `Feral Interactive/GRIDLegends/Preferences Data`). A flat screen is forgiving:
a steady 30 or 60 fps is the target.

### Phase 7 — Packaging

`tools/vxmac_grid.py doctor | prepare --team | build | install | copy | launch | pull`, a setup guide,
and the same warnings as VXpro: never uninstall the host (it deletes the copied data and saves), keep the
same bundle id and team for updates, paid Developer Program account (Increased Memory Limit, Extended
Virtual Addressing). Game files never go in git or releases.

## 4. Risks and open questions

| Risk | Likelihood | Mitigation / decision |
|---|---|---|
| Receipt validation blocks startup | Ruled out on the Mac (Phase 0) | Receipt only used for online login |
| Feral pre-game launcher (AppKit + WebKit) | Certain | Seed `GameOptionsDialogShouldShow = 0` before first launch |
| IOHID-only controller support | Certain | Virtual HID pad (Phase 3) |
| Run-time-only AppKit/Feral UI calls (alerts, launcher-style dialogs, WebView UI) | High | libvxkit catch-all logs; implement what is hit |
| StoreKit DLC/IAP ownership and CloudKit saves unavailable after re-signing | High | Base game offline; saves local only |
| Online multiplayer / EA services | High | Expect offline only at first |
| Mac binary archives incompatible on M2 headset | Medium | Disable them, let Metal compile |
| Memory over the ~8 GB limit | Low–medium | Lowest textures; reservation check in Phase 0 |

## 5. Milestones

1. Converted dylib loads on the Mac (`dyhost_mac`) — **end of Phase 0**
2. `check_imports`: 0 missing; game reaches startup in the simulator
3. Main menu on the headset in a panel
4. A full race with a gamepad and sound — **playable**
5. One-command setup tool and guide

Out of scope for now: stereo 3D, head-tracked camera, steering wheels.

## What you need

- Apple-silicon Mac, Xcode 26+ with the visionOS SDK (27.2 is installed), XcodeGen, Python 3
- Vision Pro in Developer Mode, paired, ~40 GB free
- Paid Apple Developer Program team
- An MFi/Xbox/PlayStation controller
