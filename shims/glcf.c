// libglcf: CoreFoundation for GRID Legends. Re-exports CoreFoundation; CFBundleGetMainBundle is answered with the
// game's own bundle at $GL_BUNDLE_PATH (the host app's Documents/GRIDLegends.app: Contents/Info.plist and
// Contents/Resources/Data). Only the game image binds to this library, so the host's main bundle is untouched.
// CFRunLoopGetMain is the game thread's run loop (the one it pumps in nextEventMatchingMask), as on a Mac where the
// game runs on the main thread; work it queues for "the main thread" then runs where it expects it.
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include "glcommon.h"

static CFBundleRef real_main_bundle(void) {
    static CFBundleRef (*real)(void);
    if (!real) real = (CFBundleRef (*)(void))dlsym(dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_NOLOAD | RTLD_LAZY), "CFBundleGetMainBundle");
    return real ? real() : NULL;
}

CFBundleRef gl_game_bundle(void) {
    static CFBundleRef b;
    static dispatch_once_t o;
    dispatch_once(&o, ^{
        const char *p = getenv("GL_BUNDLE_PATH");
        if (!p || !*p) return;
        CFURLRef u = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)p, (CFIndex)strlen(p), true);
        b = u ? CFBundleCreate(NULL, u) : NULL;
        if (u) CFRelease(u);
        CFStringRef id = b ? CFBundleGetIdentifier(b) : NULL;
        char ids[128] = "";
        if (id) CFStringGetCString(id, ids, sizeof ids, kCFStringEncodingUTF8);
        vxmac_log("GRID shim: main bundle -> %s (%s)", p, b ? (*ids ? ids : "no identifier") : "NOT A BUNDLE");
    });
    return b;
}

CFBundleRef CFBundleGetMainBundle(void) {
    CFBundleRef b = gl_game_bundle();
    return b ? b : real_main_bundle();
}

CFRunLoopRef CFRunLoopGetMain(void) {
    CFRunLoopRef r = (CFRunLoopRef)gl_program_runloop();
    if (r) { gl_log_once("CoreFoundation: CFRunLoopGetMain -> the game thread's run loop"); return r; }
    static CFRunLoopRef (*real)(void);
    if (!real) real = (CFRunLoopRef (*)(void))dlsym(dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_NOLOAD | RTLD_LAZY), "CFRunLoopGetMain");
    return real();
}
