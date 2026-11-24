# Phase 0 results (2026-11-23, Mac)

Game: `/Applications/GRIDLegends.app`, Feral RC9, build 376070.68732.33491, executable (thin arm64)
SHA-256 `73e7a8fe7741b07ab36128dcea1a7ca890a45a7255d6d4b463bddcebb662004e`. Reproduce with
[`tools/mac_trial.sh`](../tools/mac_trial.sh).

## Verdict: go on the Mac; blocked in the visionOS simulator by Feral's activation (see [Phase 1](PHASE1.md))

| Gate | Result |
|---|---|
| Converted game loads | **Pass.** `macho_prepare.py --as-dylib` (macOS platform) → `dyhost_mac -n`: all fixups and C++ initializers ran. entry_offset 65472 (0xFFC0). |
| Receipt / licence | **Pass on the Mac only** (see [Phase 1](PHASE1.md): Feral's online activation fails in the visionOS simulator, `_Exit(173)`). Run from a stand-in bundle (`com.example.gridtest`, no `_MASReceipt`, ad-hoc signed): launcher → title screen → "No save game found, create one?". No licence prompt, no exit. |
| Large memory reservations | **No pool patch needed (provisional).** See below. |

## Receipt: what the code does

- `appStoreReceiptURL` appears only as a name passed to `sel_registerName` in a large start-up table of
  Foundation selectors (`0x1010e82d4`, stored at `0x102f362a8`). No direct load of that slot was found.
- The other "receipt" strings sit next to `steamticket`, `licence`, `licenceid`, `password`, `token` and
  `access_token`: an online login payload and a log-redaction list (Feral/EA online services), not a start-up check.
- Conclusion at the time: the receipt only matters for online features. **Wrong:** Feral's own activation
  (`CActivation`) also gates start-up; on this Mac it passed with the real install's activation reachable. See Phase 1.

## Memory (title screen, Mac, M-series)

- Footprint: 4.9–5.2 GB at the title screen, **including the launcher's WebKit**. In-race memory is not
  measured yet (the background input tools could not drive the menus). Still to check, against the headset's ~8 GB.
- Big virtual regions: one 385 GB guard and 13.8 + 1.8 GB `rwx` regions at `0x7000000000+`. Phase 0 took these for
  JavaScriptCore's; **Phase 1 showed the 16 GB at `0x7000000000` is the game's own reservation** (`GRIDLegends.dylib+0x1145c20`). Engine-owned reservations
  are small ("Untagged" total 16.3 GB, of which 15.6 GB is the JSC pair above).
- Cyberpunk needed its pool patch because a 64 GB reservation failed on the headset. Nothing comparable
  here, and the launcher (with its WebKit) will not run on the headset.
- `AGX: exceeded compiled variants footprint limit` was logged once: Metal shader-variant pressure, worth
  watching on the headset.

## New findings for later phases

- **Pre-game launcher.** Feral's "GRID Legends Options" window (AppKit + WebKit, `FeralUI`) appears
  first, then the usage-statistics consent and a controls notice, all before the game starts. On the
  headset, skip it with the preference `GameOptionsDialogShouldShow = 0` in
  `Library/Application Support/Feral Interactive/GRIDLegends/Preferences Data` (XML), seeded by the host
  before first launch. Also seed the consent answer (do not send) so that web dialog never needs to render.
- **Settings and saves location.** A non-sandboxed run writes to
  `~/Library/Application Support/Feral Interactive/GRIDLegends/` (`Preferences Data`, `VFS/{User,Storage,Local,Temp}`,
  `cache`, `FeralCrashReports`). On visionOS this becomes the app container's Library, so saves live in
  the host app's container (same warning as VXpro: never uninstall the host).
- The game started from `Contents/Resources/Data` through the symlinked `Resources`. The bundle-path
  redirect in Phase 1 only needs `NSBundle mainBundle` to point at a folder containing `Contents/Resources`.
- `Remote notification support is unavailable`: harmless (no push entitlement).

## Side effects on this Mac

The test copy created `~/Library/Application Support/Feral Interactive/GRIDLegends/` and
`~/Library/Preferences/com.example.gridtest.plist`. The App Store game's own data in
`~/Library/Containers/com.feralinteractive.gridlegends` was not touched. Delete those two paths to clean up.
