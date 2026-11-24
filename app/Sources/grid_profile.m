// grid_profile.m: what the host does for GRID Legends before the game starts (called from host.m; tools/sync_host.py).
//
// The game's files on the headset (copied by tools/vxmac_grid.py copy), in the app's Documents:
//   GRIDLegends.app/Contents/Info.plist          the game's own Info.plist
//   GRIDLegends.app/Contents/Resources/...       its Resources (Data/ is 34 GB)
//   GRIDLegends.app/Contents/MacOS/GRIDLegends   an empty placeholder made here (_NSGetExecutablePath, libvxsystem)
// The game's main bundle (libglcf, libglfoundation) is that folder: GL_BUNDLE_PATH.
// Its settings: Library/Application Support/Feral Interactive/GRIDLegends/Preferences Data (Feral's registry XML).
// Before the first launch it is seeded so the Mac-only pre-game launcher and its consent prompts never open; usage
// data and crash reports are declined; and the game starts on Feral's Low preset at 1280x720 (ShouldLoadDefaultPreset 0:
// the detected "high" preset ran out of the app's ~8 GB loading a race; Low peaks at ~7.0 GB in a race), 60 fps
// (FramerateLimit; races ran at ~59 fps on an M2), and Feral's pipeline cache harvesting off (HarvestBinaryArchive 0
// under Software\IndirectX\Direct3D\Config: it kept growing a binary archive in memory, ~0.8 GB at the title screen).
// The settings can be changed in the game's options. An existing file keeps everything but the launcher switch.
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <execinfo.h>
#include <stdlib.h>
#include <string.h>

void vxmac_log(const char *fmt, ...);

// (diagnostics: who ends the process. exit() runs atexit handlers on the calling thread, so its stack shows the caller;
//  frames in the game are printed as GRIDLegends.dylib+offset, the offsets of tools/grid_prepare.py's input)
static void grid_atexit(void) {
    void *f[48]; int n = backtrace(f, 48);
    for (int i = 0; i < n; i++) {
        Dl_info d;
        if (dladdr(f[i], &d) && d.dli_fname) {
            const char *b = strrchr(d.dli_fname, '/');
            vxmac_log("GRID: exit stack %2d %s+%#lx %s", i, b ? b + 1 : d.dli_fname, (unsigned long)((char *)f[i] - (char *)d.dli_fbase), d.dli_sname ? d.dli_sname : "");
        } else vxmac_log("GRID: exit stack %2d %p", i, f[i]);
    }
}

// (defaults only: -env NAME=VALUE on the launch command line wins)
void grid_profile_env(void) {
    atexit(grid_atexit);
    setenv("VXRT_VR_MODE", "screen", 0);            // the presenter's world-locked screen only: never head-driven VR
    setenv("VXMAC_GPU_WORKING_SET_MB", "4096", 0);  // the GPU budget the game is told (the app's limit is ~8 GB in all)
    setenv("GL_DISPLAY_HZ", "90", 0);               // CVDisplayLink stand-in (libglcv)
    // (Metal's Mac1/Mac2 GPU families answered yes, as on the Mac the game was built for: the same M-series GPU says no
    //  on visionOS, and Feral then chose another video format path whose colour planes came out scrambled; libvxmtl)
    setenv("VXMAC_GPU_FAMILY_MAC", "1", 0);
}

static NSString *const kSeed =
    @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
     "<registry>\n"
     "    <key name=\"HKEY_CURRENT_USER\">\n"
     "        <key name=\"Software\">\n"
     "            <key name=\"IndirectX\">\n"
     "                <key name=\"Direct3D\">\n"
     "                    <key name=\"Config\">\n"
     "                        <value name=\"HarvestBinaryArchive\" type=\"integer\">0</value>\n"
     "                    </key>\n"
     "                </key>\n"
     "            </key>\n"
     "            <key name=\"Feral Interactive\">\n"
     "                <key name=\"GRIDLegends\">\n"
     "                    <key name=\"GraphicsSettings\">\n"
     "                        <value name=\"AmbientOcclusion\" type=\"integer\">0</value>\n"
     "                        <value name=\"AntiAliasing\" type=\"integer\">1</value>\n"
     "                        <value name=\"Crowds\" type=\"integer\">0</value>\n"
     "                        <value name=\"GroundCover\" type=\"integer\">0</value>\n"
     "                        <value name=\"LODQuality\" type=\"integer\">0</value>\n"
     "                        <value name=\"LightingQuality\" type=\"integer\">0</value>\n"
     "                        <value name=\"Mirrors\" type=\"integer\">0</value>\n"
     "                        <value name=\"Particles\" type=\"integer\">0</value>\n"
     "                        <value name=\"PostProcess\" type=\"integer\">0</value>\n"
     "                        <value name=\"ScreenSpaceReflections\" type=\"integer\">0</value>\n"
     "                        <value name=\"Shadows\" type=\"integer\">0</value>\n"
     "                        <value name=\"Skidmarks\" type=\"integer\">0</value>\n"
     "                        <value name=\"SmokeShadows\" type=\"integer\">0</value>\n"
     "                        <value name=\"TextureQuality\" type=\"integer\">0</value>\n"
     "                        <value name=\"VehicleReflections\" type=\"integer\">0</value>\n"
     "                        <value name=\"VolumetricLights\" type=\"integer\">0</value>\n"
     "                        <value name=\"WeatherEffects\" type=\"integer\">0</value>\n"
     "                        <value name=\"FramerateLimit\" type=\"integer\">60</value>\n"
     "                    </key>\n"
     "                    <key name=\"Setup\">\n"
     "                        <value name=\"AllowSendCrashReports\" type=\"integer\">0</value>\n"
     "                        <value name=\"AllowSendUsageData\" type=\"integer\">0</value>\n"
     "                        <value name=\"GameOptionsDialogShouldShow\" type=\"integer\">0</value>\n"
     "                        <value name=\"GameOptionsDialogShown\" type=\"integer\">1</value>\n"
     "                        <value name=\"ShouldLoadDefaultPreset\" type=\"integer\">0</value>\n"
     "                        <value name=\"SoftwareUpdatedAskedUser\" type=\"integer\">1</value>\n"
     "                        <key name=\"Apple M2 GPU\">\n"
     "                            <value name=\"FullScreen\" type=\"integer\">1</value>\n"
     "                            <value name=\"ScreenW\" type=\"integer\">1280</value>\n"
     "                            <value name=\"ScreenH\" type=\"integer\">720</value>\n"
     "                        </key>\n"
     "                        <key name=\"SpecificationAlerts\">\n"
     "                            <value name=\"DocsAndControlsSelectedPadsNoMouse\" type=\"integer\">1</value>\n"
     "                        </key>\n"
     "                    </key>\n"
     "                </key>\n"
     "            </key>\n"
     "        </key>\n"
     "    </key>\n"
     "</registry>\n";

static void seed_preferences(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [support stringByAppendingPathComponent:@"Feral Interactive/GRIDLegends"];
    NSString *file = [dir stringByAppendingPathComponent:@"Preferences Data"];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *xml = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil];
    if (!xml) {
        BOOL ok = [kSeed writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
        vxmac_log("GRID: preferences seeded (launcher off, usage data and crash reports declined): %s", ok ? "ok" : "FAILED");
        return;
    }
    // (an existing file: only the launcher switch is forced off)
    NSString *on = @"<value name=\"GameOptionsDialogShouldShow\" type=\"integer\">1</value>";
    if ([xml containsString:on]) {
        xml = [xml stringByReplacingOccurrencesOfString:on withString:@"<value name=\"GameOptionsDialogShouldShow\" type=\"integer\">0</value>"];
        [xml writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
        vxmac_log("GRID: preferences: pre-game launcher switched off");
    }
}

// The game's folder in Documents: returns the executable placeholder's path (for VXMAC_EXECUTABLE_PATH), or nil when
// the game's data is not there yet.
NSString *grid_prepare_data(NSString *root) {
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL dir = NO;
    if (![fm fileExistsAtPath:[root stringByAppendingPathComponent:@"Contents/Resources/Data"] isDirectory:&dir] || !dir) return nil;
    if (![fm fileExistsAtPath:[root stringByAppendingPathComponent:@"Contents/Info.plist"]])
        vxmac_log("GRID: %s/Contents/Info.plist is missing (copy it with the data)", root.UTF8String);
    NSString *macos = [root stringByAppendingPathComponent:@"Contents/MacOS"];
    [fm createDirectoryAtPath:macos withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *exe = [macos stringByAppendingPathComponent:@"GRIDLegends"];
    if (![fm fileExistsAtPath:exe]) [NSData.data writeToFile:exe atomically:NO];
    setenv("GL_BUNDLE_PATH", root.UTF8String, 1);
    seed_preferences();
    return exe;
}

// The game's CAMetalLayer for the floating window (-present flat). VXpro looks only at the key window's content view;
// Feral draws into a child view (CFeralMetalView), so the window's views are searched, depth first.
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
static CALayer *find_in_layer(CALayer *l, int depth) {
    if (!l || depth > 8) return nil;
    if ([l isKindOfClass:[CAMetalLayer class]]) return l;
    for (CALayer *s in l.sublayers) { CALayer *m = find_in_layer(s, depth + 1); if (m) return m; }
    return nil;
}
static CALayer *find_metal_layer(id view, int depth) {
    if (!view || depth > 12) return nil;
    if ([view respondsToSelector:@selector(layer)]) {
        // (the view's own layer, or a CAMetalLayer the game added under it)
        CALayer *l = find_in_layer(((id (*)(id, SEL))objc_msgSend)(view, @selector(layer)), 0);
        if (l) return l;
    }
    if ([view respondsToSelector:@selector(subviews)])
        for (id v in ((NSArray *(*)(id, SEL))objc_msgSend)(view, @selector(subviews))) {
            CALayer *l = find_metal_layer(v, depth + 1);
            if (l) return l;
        }
    return nil;
}
void *grid_metal_layer(void) {
    // (libvxkit's NSApp, read only: calling +sharedApplication here would create a plain NSApplication before the game
    //  makes its CFeralNSApplication, and the game would run with the wrong application object)
    static __unsafe_unretained id *nsapp_p;
    if (!nsapp_p) nsapp_p = (__unsafe_unretained id *)dlsym(RTLD_DEFAULT, "NSApp");
    id nsapp = nsapp_p ? *nsapp_p : nil;
    if (!nsapp) return NULL;
    NSMutableArray *wins = [NSMutableArray array];
    id key = [nsapp respondsToSelector:@selector(keyWindow)] ? ((id (*)(id, SEL))objc_msgSend)(nsapp, @selector(keyWindow)) : nil;
    if (key) [wins addObject:key];
    if ([nsapp respondsToSelector:@selector(windows)]) [wins addObjectsFromArray:((NSArray *(*)(id, SEL))objc_msgSend)(nsapp, @selector(windows)) ?: @[]];
    for (id w in wins) {
        id content = [w respondsToSelector:@selector(contentView)] ? ((id (*)(id, SEL))objc_msgSend)(w, @selector(contentView)) : nil;
        CALayer *l = find_metal_layer(content, 0);
        if (l) return (__bridge void *)l;
    }
    static int logged;
    if (wins.count && !logged++) {   // (once, when there are windows: what they hold, if no layer is found)
        for (id w in wins) {
            id content = ((id (*)(id, SEL))objc_msgSend)(w, @selector(contentView));
            NSArray *subs = content ? ((NSArray *(*)(id, SEL))objc_msgSend)(content, @selector(subviews)) : nil;
            CALayer *cl = content ? ((id (*)(id, SEL))objc_msgSend)(content, @selector(layer)) : nil;
            vxmac_log("GRID: window %s content %s layer %s sublayers %lu subviews %lu", class_getName([w class]),
                      content ? class_getName([content class]) : "nil", cl ? class_getName([cl class]) : "nil",
                      (unsigned long)cl.sublayers.count, (unsigned long)subs.count);
            for (id v in subs) {
                CALayer *vl = ((id (*)(id, SEL))objc_msgSend)(v, @selector(layer));
                vxmac_log("GRID:   subview %s layer %s sublayers %lu", class_getName([v class]), vl ? class_getName([vl class]) : "nil", (unsigned long)vl.sublayers.count);
            }
        }
    }
    return NULL;
}

// (the floating window can be resized: the game's layer follows the window's view; added to host.m's
//  VXMacRootController at load, since that class is generated from VXpro's source)
#import <UIKit/UIKit.h>
#import <GameController/GameController.h>
static void grid_layout(UIViewController *self, SEL _cmd) {
    for (CALayer *l in self.view.layer.sublayers)
        if ([l isKindOfClass:[CAMetalLayer class]]) l.frame = self.view.bounds;
    // (visionOS turns a controller's buttons into pinches on the view you look at unless the view says it takes
    //  controller input itself: then every button goes to GameController only, and on to the game's virtual pad)
    BOOL has = NO;
    for (id<UIInteraction> i in self.view.interactions) if ([i isKindOfClass:[GCEventInteraction class]]) has = YES;
    if (!has) {
        GCEventInteraction *gi = [GCEventInteraction new];
        gi.handledEventTypes = GCUIEventTypeGamepad;
        [self.view addInteraction:gi];
        vxmac_log("GRID: the window's game view takes controller input (GCEventInteraction)");
    }
}
__attribute__((constructor)) static void grid_window_layout(void) {
    Class c = objc_getClass("VXMacRootController");
    if (c) class_addMethod(c, @selector(viewDidLayoutSubviews), (IMP)grid_layout, "v@:");
}
