// libgliokit: IOKit for GRID Legends. Re-exports libvxiokit (VXpro: IOKit + the display calls) and keeps the game's
// device and power watchers alive where the app sandbox refuses them. On the headset IONotificationPortCreate fails
// (no IOKit notification port for apps); the game does not check and crashed in IONotificationPortGetRunLoopSource(NULL).
// A failed port becomes a stand-in whose run loop source never fires: no USB devices arrive, no power events, which is
// what a headset has anyway. Calls that succeed are passed through untouched.
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include "glcommon.h"

static void *real(const char *name) {
    static void *iokit;
    if (!iokit) iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOLOAD | RTLD_LAZY);
    return dlsym(iokit, name);
}

static char g_fake_port_storage;
#define FAKE_PORT ((IONotificationPortRef)(void *)&g_fake_port_storage)

static CFRunLoopSourceRef quiet_source(void) {
    static CFRunLoopSourceRef s;
    if (!s) { CFRunLoopSourceContext c = {0}; s = CFRunLoopSourceCreate(NULL, 0, &c); }   // (never signalled)
    return s;
}

IONotificationPortRef IONotificationPortCreate(mach_port_t main) {
    IONotificationPortRef p = ((IONotificationPortRef (*)(mach_port_t))real("IONotificationPortCreate"))(main);
    if (p) return p;
    gl_log_once("IOKit: IONotificationPortCreate refused -> a quiet stand-in port (no device or power notifications)");
    return FAKE_PORT;
}
CFRunLoopSourceRef IONotificationPortGetRunLoopSource(IONotificationPortRef p) {
    if (!p || p == FAKE_PORT) return quiet_source();
    return ((CFRunLoopSourceRef (*)(IONotificationPortRef))real("IONotificationPortGetRunLoopSource"))(p);
}
void IONotificationPortDestroy(IONotificationPortRef p) {
    if (!p || p == FAKE_PORT) return;
    ((void (*)(IONotificationPortRef))real("IONotificationPortDestroy"))(p);
}
kern_return_t IOServiceAddMatchingNotification(IONotificationPortRef p, const io_name_t type, CFDictionaryRef matching,
                                               IOServiceMatchingCallback cb, void *ref, io_iterator_t *it) {
    if (!p || p == FAKE_PORT) {
        if (matching) CFRelease(matching);   // (the call consumes one reference to the matching dictionary)
        if (it) *it = IO_OBJECT_NULL;        // (IOIteratorNext(0) returns 0: nothing matched)
        gl_log_once("IOKit: IOServiceAddMatchingNotification on the stand-in port -> no devices");
        return KERN_SUCCESS;
    }
    return ((kern_return_t (*)(IONotificationPortRef, const char *, CFDictionaryRef, IOServiceMatchingCallback, void *, io_iterator_t *))
            real("IOServiceAddMatchingNotification"))(p, type, matching, cb, ref, it);
}
io_connect_t IORegisterForSystemPower(void *ref, IONotificationPortRef *port, void *cb, io_object_t *notifier) {
    io_connect_t r = ((io_connect_t (*)(void *, IONotificationPortRef *, void *, io_object_t *))real("IORegisterForSystemPower"))(ref, port, cb, notifier);
    if (port && !*port) {
        *port = FAKE_PORT;
        gl_log_once("IOKit: IORegisterForSystemPower refused -> a quiet stand-in port (no power events)");
    }
    return r;
}

// (power sources: a refused run loop source becomes a quiet one)
CFRunLoopSourceRef IOPSNotificationCreateRunLoopSource(void (*cb)(void *), void *ctx) {
    CFRunLoopSourceRef s = ((CFRunLoopSourceRef (*)(void (*)(void *), void *))real("IOPSNotificationCreateRunLoopSource"))(cb, ctx);
    if (s) return s;
    gl_log_once("IOKit: IOPSNotificationCreateRunLoopSource refused -> a quiet source");
    return (CFRunLoopSourceRef)CFRetain(quiet_source());   // (the caller owns and releases it)
}
