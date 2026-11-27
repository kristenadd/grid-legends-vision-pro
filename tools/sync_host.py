#!/usr/bin/env python3
"""sync_host.py: app/Sources/host.m = VXpro's host.m (third_party/VXpro/app/Sources/host.m) with GRID's hooks.

    tools/sync_host.py           write app/Sources/host.m
    tools/sync_host.py --check   exit 1 if app/Sources/host.m is not what this script makes (CI / after a VXpro update)

Every other host source is used from the submodule as it is (app/project.yml). The hooks, each an exact replacement
that must match once (the script stops when VXpro's text changed, so the update is looked at by hand):
  1. the default image: GRIDLegends when its dylib is embedded;
  2. GRID's launch defaults (grid_profile_env in app/Sources/grid_profile.m) and a floating window instead of the
     immersive space unless the launch says -present vr;
  3. Cyberpunk's UserSettings.json reading only for Cyberpunk;
  4. GRID's data folder: Documents/GRIDLegends.app/Contents/Resources/Data (grid_prepare_data);
  5. the floating window finds the game's Metal layer in a child view too (grid_metal_layer);
  6. a burst of frames on request (grid_burst in app/Sources/grid_burst.m; tools/vxmac_grid.py burst), and the
     splash watching for the game's first picture (grid_splash_frame in app/Sources/grid_splash.m);
  7. a quiet build (GRID_QUIET, tools/vxmac_grid.py build --quiet): the logs go to /dev/null and no snapshots are taken.
"""
import os, subprocess, sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(HERE, 'third_party', 'VXpro', 'app', 'Sources', 'host.m')
DST = os.path.join(HERE, 'app', 'Sources', 'host.m')

HOOKS = [
    # 1
    ('''    if (!*g_image) snprintf(g_image, sizeof g_image, "%s",
        [NSFileManager.defaultManager fileExistsAtPath:[fw stringByAppendingPathComponent:@"Cyberpunk2077.dylib"]] ? "Cyberpunk2077" : "vxmac_test");''',
     '''    if (!*g_image) snprintf(g_image, sizeof g_image, "%s",
        [NSFileManager.defaultManager fileExistsAtPath:[fw stringByAppendingPathComponent:@"GRIDLegends.dylib"]] ? "GRIDLegends" :
        [NSFileManager.defaultManager fileExistsAtPath:[fw stringByAppendingPathComponent:@"Cyberpunk2077.dylib"]] ? "Cyberpunk2077" : "vxmac_test");'''),
    # 2
    ('''    if (!prog.count && !strcmp(g_image, "vxmac_test"))''',
     '''    if (!strcmp(g_image, "GRIDLegends")) { void grid_profile_env(void); grid_profile_env(); }   // (GRID: grid_profile.m)
    if (!strcmp(g_image, "GRIDLegends") && ![a containsObject:@"-present"]) g_vr = 0;   // (GRID: a floating window by default)
    if (!prog.count && !strcmp(g_image, "vxmac_test"))'''),
    # 3
    ('''            NSString *usPath = [lib stringByAppendingPathComponent:@"CD Projekt Red/Cyberpunk 2077/UserSettings.json"];
            NSData *js = [NSData dataWithContentsOfFile:usPath];''',
     '''            NSString *usPath = [lib stringByAppendingPathComponent:@"CD Projekt Red/Cyberpunk 2077/UserSettings.json"];
            NSData *js = !strcmp(g_image, "Cyberpunk2077") ? [NSData dataWithContentsOfFile:usPath] : nil;   // (GRID: Cyberpunk only)'''),
    # 4
    ('''        BOOL dir = NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:[root stringByAppendingPathComponent:@"Contents/Data"] isDirectory:&dir] && dir) {''',
     '''        BOOL dir = NO;
        NSString *grid_prepare_data(NSString *root);   // (GRID: grid_profile.m)
        NSString *gridExe = !strcmp(g_image, "GRIDLegends") ? grid_prepare_data(root) : nil;
        if (gridExe) {
            setenv("VXMAC_EXECUTABLE_PATH", gridExe.UTF8String, 1);
            jlog("game_data", "\\"root\\":\\"%s\\"", root.UTF8String);
        } else if (!strcmp(g_image, "GRIDLegends")) {
            jlog("game_data", "\\"root\\":null,\\"looked_in\\":\\"%s/Contents/Resources/Data\\"", root.UTF8String);
        } else if ([NSFileManager.defaultManager fileExistsAtPath:[root stringByAppendingPathComponent:@"Contents/Data"] isDirectory:&dir] && dir) {'''),
    # 5
    ('''    CALayer *l = (__bridge CALayer *)vxkit_metal_layer();''',
     '''    void *grid_metal_layer(void);   // (GRID: grid_profile.m - Feral's layer is on a child view)
    CALayer *l = (__bridge CALayer *)(vxkit_metal_layer() ?: grid_metal_layer());'''),
    ('''    if (!l || l.superlayer) return;
    l.frame = self.view.bounds; l.contentsGravity = kCAGravityResizeAspect;''',
     '''    if (!l || l.superlayer == self.view.layer) return;
    [l removeFromSuperlayer];   // (GRID: Feral's layer may sit in a child view's (never shown) layer)
    l.frame = self.view.bounds; l.contentsGravity = kCAGravityResizeAspect;'''),
    # 6
    ("""    if (g_snap_s > 0 && tn - g_snap_last >= g_snap_s) { g_snap_last = tn; snapshot((__bridge id<MTLCommandBuffer>)cb, (__bridge id<MTLTexture>)tex); }""",
     """    if (g_snap_s > 0 && tn - g_snap_last >= g_snap_s) { g_snap_last = tn; snapshot((__bridge id<MTLCommandBuffer>)cb, (__bridge id<MTLTexture>)tex); }
    { void grid_burst(void *, void *, double); grid_burst(cb, tex, tn); }   // (GRID: grid_burst.m)
    { void grid_splash_frame(void *, void *); grid_splash_frame(cb, tex); }   // (GRID: grid_splash.m)"""),
    # 7
    ('''    snprintf(p, sizeof p, "%s/vxmac_host.jsonl", g_docs);
    g_log = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    snprintf(p, sizeof p, "%s/vxmac_program.log", g_docs);''',
     '''#ifdef GRID_QUIET   // (GRID: tools/vxmac_grid.py build --quiet - no log files, no snapshots)
    snprintf(p, sizeof p, "/dev/null");
    g_log = open(p, O_WRONLY);
    g_snap_s = 0;
#else
    snprintf(p, sizeof p, "%s/vxmac_host.jsonl", g_docs);
    g_log = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    snprintf(p, sizeof p, "%s/vxmac_program.log", g_docs);
#endif'''),
]


def make():
    text = open(SRC).read()
    for i, (old, new) in enumerate(HOOKS, 1):
        n = text.count(old)
        if n != 1:
            raise SystemExit('hook %d: VXpro host.m text found %d times (expected once): update tools/sync_host.py' % (i, n))
        text = text.replace(old, new)
    rev = subprocess.run(['git', '-C', os.path.dirname(SRC), 'rev-parse', '--short', 'HEAD'], capture_output=True, text=True).stdout.strip()
    head = ('// GENERATED by tools/sync_host.py from VXpro %s app/Sources/host.m with GRID Legends\' hooks. Do not edit:\n'
            '// change the hooks in tools/sync_host.py or app/Sources/grid_profile.m.\n'
            '// Based on VXpro, Copyright (c) 2026 Ag3497120, MIT License (third_party/VXpro/LICENSE).\n' % (rev or '?'))
    return head + text


def main():
    out = make()
    if '--check' in sys.argv:
        same = os.path.exists(DST) and open(DST).read() == out
        print('host.m up to date' if same else 'host.m differs: run tools/sync_host.py')
        raise SystemExit(0 if same else 1)
    os.makedirs(os.path.dirname(DST), exist_ok=True)
    open(DST, 'w').write(out)
    print('wrote', DST)


if __name__ == '__main__':
    main()
