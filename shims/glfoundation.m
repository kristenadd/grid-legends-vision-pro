// libglfoundation: Foundation for GRID Legends. Re-exports Foundation and adds:
// - NSUserNotificationCenter (macOS only): a stand-in that delivers nothing;
// - +[NSBundle mainBundle] answered with the game's bundle ($GL_BUNDLE_PATH, libglcf) when the game image itself asks.
//   The game calls it through objc_msgSend, so the library it binds to cannot scope it: the caller's address does.
// - -[NSBundle appStoreReceiptURL] of the game's bundle: Contents/_MASReceipt/receipt, where the Mac keeps it (the
//   receipt itself is the user's own, copied unchanged; nothing here reads or alters it). Every call is logged once.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <stdlib.h>
#include <string.h>
#include "glcommon.h"

@interface NSUserNotificationCenter : NSObject @end
@implementation NSUserNotificationCenter
GL_CATCHALL
+ (instancetype)defaultUserNotificationCenter { static NSUserNotificationCenter *c; static dispatch_once_t o; dispatch_once(&o, ^{ c = [self new]; }); return c; }
@end

// ---- the game's main bundle ----
static const void *g_game_base;
static const char *game_image_name(void) { const char *n = getenv("GL_GAME_IMAGE"); return n && *n ? n : "GRIDLegends.dylib"; }

static const void *game_base(void) {
    if (g_game_base) return g_game_base;
    const char *want = game_image_name();
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *n = _dyld_get_image_name(i), *s = strrchr(n, '/');
        if (!strcmp(s ? s + 1 : n, want)) { g_game_base = _dyld_get_image_header(i); break; }
    }
    return g_game_base;
}

static NSBundle *(*g_orig_main)(id, SEL);
static NSBundle *game_main_bundle(id self, SEL _cmd) {
    static NSBundle *gb;
    void *ret = __builtin_return_address(0);
    const void *base = game_base();
    if (base) {
        Dl_info info;
        if (dladdr(ret, &info) && info.dli_fbase == base) {
            static dispatch_once_t o;
            dispatch_once(&o, ^{
                const char *p = getenv("GL_BUNDLE_PATH");
                if (p && *p) gb = [NSBundle bundleWithPath:@(p)];
                vxmac_log("GRID shim: +[NSBundle mainBundle] for the game -> %s", gb ? gb.bundlePath.UTF8String : "(host bundle)");
            });
            if (gb) return gb;
        }
    }
    return g_orig_main(self, _cmd);
}

static NSURL *(*g_orig_receipt)(id, SEL);
static NSURL *game_receipt_url(NSBundle *self, SEL _cmd) {
    const char *p = getenv("GL_BUNDLE_PATH");
    NSURL *u;
    if (p && [self.bundlePath isEqualToString:@(p)])
        u = [NSURL fileURLWithPath:[@(p) stringByAppendingPathComponent:@"Contents/_MASReceipt/receipt"]];
    else
        u = g_orig_receipt(self, _cmd);
    char m[1200];
    snprintf(m, sizeof m, "Foundation: appStoreReceiptURL of %s -> %s (%s)", self.bundlePath.lastPathComponent.UTF8String,
             u.path.UTF8String ?: "nil", u && [NSFileManager.defaultManager fileExistsAtPath:u.path] ? "present" : "absent");
    gl_log_once(m);
    return u;
}

__attribute__((constructor)) static void gl_foundation_init(void) {
    if (!getenv("GL_BUNDLE_PATH")) return;
    Method m = class_getClassMethod([NSBundle class], @selector(mainBundle));
    g_orig_main = (NSBundle *(*)(id, SEL))method_setImplementation(m, (IMP)game_main_bundle);
    Method r = class_getInstanceMethod([NSBundle class], @selector(appStoreReceiptURL));
    if (r) g_orig_receipt = (NSURL *(*)(id, SEL))method_setImplementation(r, (IMP)game_receipt_url);
}
