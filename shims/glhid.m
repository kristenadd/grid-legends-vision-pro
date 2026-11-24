// glhid.m (in libgliokit): a virtual HID gamepad for GRID Legends, fed by GameController.
//
// Feral reads gamepads through IOHIDManager, which a visionOS app cannot use. Every IOHID call the game imports is
// answered here with our own objects (the real HID system is never called):
// - each GameController extended gamepad visionOS has connected is one HID device, presented as an Xbox 360 controller
//   (VendorID 0x045e, ProductID 0x028e). The buttons follow the Mac Xbox 360 driver's numbering, which the game uses
//   for this pad (found on the headset in the game's controls screen, not the order of the inputdevices.json entry):
//   1 A, 2 B, 3 X, 4 Y, 5 LB, 6 RB, 7 left stick click, 8 right stick click, 9 Start (Menu), 10 Back (View), 11 Guide;
//   axes leftx:a0 lefty:a1 lefttrigger:a2 rightx:a3 righty:a4 righttrigger:a5; the d-pad as the hat;
//   GL_PAD_VID / GL_PAD_PID present another entry of that file instead;
// - elements: buttons 1-11 (usage page 9, as above), axes X Y Z Rx Ry Rz (sticks -32768..32767, Y down positive; triggers on Z and
//   Rz 0..255) and a hat switch (0-7 clockwise from up, 8 centred);
// - a timer on the run loop the game schedules its manager on reads the pads every 4 ms; changed elements go to the
//   game's input value callback, and IOHIDDeviceGetValue answers the latest state; pads connecting and disconnecting
//   are the manager's matching and removal callbacks.
// Every IOHID function's first call is logged (the game's way of reading pads, for the next step).
// GL_PAD_LOG=1 logs the pad's button and hat changes.
// A button press is reported for at least 100 ms (GL_PAD_MIN_PRESS_MS): the game polls the pad once a frame, and some
// buttons (Menu) arrive from GameController as pulses shorter than a frame.
// Test switch: GL_PAD_TEST=<button usage>@<seconds> presses that HID button by itself for 0.3 s at that many seconds
// after the manager opened (to see what the game makes of it without anyone at the controller).
#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#include <mach/mach_time.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include "glcommon.h"

#define L(name) gl_log_once("HID: " name)
typedef int32_t IOReturn_;
enum { kIOReturnSuccess_ = 0, kIOReturnUnsupported_ = (int32_t)0xe00002c7, kIOReturnNotFound_ = (int32_t)0xe00002f0 };
enum { kTypeMisc = 1, kTypeButton = 2 };
enum { kPageDesktop = 0x01, kPageButton = 0x09 };
enum { kUsageGamePad = 0x05, kX = 0x30, kY = 0x31, kZ = 0x32, kRx = 0x33, kRy = 0x34, kRz = 0x35, kHat = 0x39 };

typedef void (*device_cb)(void *ctx, IOReturn_ result, void *sender, void *device);
typedef void (*value_cb)(void *ctx, IOReturn_ result, void *sender, void *value);

@class GLHIDDevice;
@interface GLHIDElement : NSObject {
@public
    __unsafe_unretained GLHIDDevice *dev; uint32_t type, page, usage, cookie; int32_t lmin, lmax, pmin, pmax;
    _Atomic int64_t value; _Atomic uint64_t stamp;
}
@end
@implementation GLHIDElement @end

@interface GLHIDValue : NSObject { @public GLHIDElement *elem; int64_t value; uint64_t stamp; uint8_t bytes[8]; } @end
@implementation GLHIDValue @end

@interface GLHIDDevice : NSObject {
@public
    NSMutableDictionary *props; NSArray<GLHIDElement *> *elements; GLHIDValue *latest[32]; __weak GCController *pad;
    double pressed_at[11];   // (when each button's current press began, for the minimum press time)
}
@end
@implementation GLHIDDevice @end

@interface GLHIDManager : NSObject {
@public
    NSArray *matching; device_cb match_cb, remove_cb; void *match_ctx, *remove_ctx; value_cb value_cb_; void *value_ctx;
    CFRunLoopRef runloop; CFStringRef mode; CFRunLoopTimerRef timer; BOOL open;
    NSMutableArray<GLHIDDevice *> *announced;
}
@end
@implementation GLHIDManager @end

// ---- the pads ----------------------------------------------------------------------------------------------------------
static NSMutableArray<GLHIDDevice *> *g_devices;   // (one per GameController pad, kept while it is connected)
static NSMutableArray<GLHIDManager *> *g_managers;
static NSObject *g_lock;

static int env_hex(const char *name, int dflt) { const char *e = getenv(name); return e && *e ? (int)strtol(e, NULL, 0) : dflt; }

static GLHIDElement *element(GLHIDDevice *d, uint32_t type, uint32_t page, uint32_t usage, int32_t lmin, int32_t lmax, int32_t pmin, int32_t pmax, int64_t rest) {
    GLHIDElement *e = [GLHIDElement new];
    e->dev = d; e->type = type; e->page = page; e->usage = usage; e->lmin = lmin; e->lmax = lmax; e->pmin = pmin; e->pmax = pmax;
    atomic_store(&e->value, rest);
    return e;
}

static GLHIDDevice *make_device(GCController *c, int index) {
    GLHIDDevice *d = [GLHIDDevice new];
    d->pad = c;
    int vid = env_hex("GL_PAD_VID", 0x045e), pid = env_hex("GL_PAD_PID", 0x028e);
    d->props = [@{ @"VendorID": @(vid), @"ProductID": @(pid), @"Product": @"Xbox 360 Wired Controller",
                   @"Manufacturer": @"Microsoft", @"Transport": @"USB", @"PrimaryUsagePage": @(kPageDesktop),
                   @"PrimaryUsage": @(kUsageGamePad), @"LocationID": @(0x14100000 + index), @"VersionNumber": @(0x0114),
                   @"SerialNumber": [NSString stringWithFormat:@"GLPAD%d", index], @"MaxInputReportSize": @(20),
                   @"DeviceUsagePairs": @[ @{ @"DeviceUsagePage": @(kPageDesktop), @"DeviceUsage": @(kUsageGamePad) } ] } mutableCopy];
    NSMutableArray *els = [NSMutableArray array];
    for (uint32_t b = 1; b <= 11; b++) [els addObject:element(d, kTypeButton, kPageButton, b, 0, 1, 0, 1, 0)];
    uint32_t axes[6] = { kX, kY, kZ, kRx, kRy, kRz };
    for (int i = 0; i < 6; i++) {
        BOOL trig = axes[i] == kZ || axes[i] == kRz;
        [els addObject:trig ? element(d, kTypeMisc, kPageDesktop, axes[i], 0, 255, 0, 255, 0)
                            : element(d, kTypeMisc, kPageDesktop, axes[i], -32768, 32767, -32768, 32767, 0)];
    }
    [els addObject:element(d, kTypeMisc, kPageDesktop, kHat, 0, 7, 0, 315, 8)];
    for (NSUInteger i = 0; i < els.count; i++) ((GLHIDElement *)els[i])->cookie = (uint32_t)i + 1;
    d->elements = els;
    return d;
}

static int64_t stick(float v) { if (v > 1) v = 1; if (v < -1) v = -1; return (int64_t)lrintf(v * 32767.f); }
static int64_t trigger(float v) { if (v > 1) v = 1; if (v < 0) v = 0; return (int64_t)lrintf(v * 255.f); }
static int64_t hat(BOOL up, BOOL right, BOOL down, BOOL left) {
    if (up && right) return 1; if (right && down) return 3; if (down && left) return 5; if (left && up) return 7;
    if (up) return 0; if (right) return 2; if (down) return 4; if (left) return 6;
    return 8;
}
// The pad's state in element order (buttons 1-11, X Y Z Rx Ry Rz, hat).
static void read_pad(GCController *c, int64_t out[18]) {
    GCExtendedGamepad *g = c.extendedGamepad;
    memset(out, 0, 18 * sizeof *out); out[17] = 8;
    if (!g) return;
    GCControllerButtonInput *buttons[11] = { g.buttonA, g.buttonB, g.buttonX, g.buttonY, g.leftShoulder, g.rightShoulder,
        g.leftThumbstickButton, g.rightThumbstickButton, g.buttonMenu, g.buttonOptions, g.buttonHome };
    for (int i = 0; i < 11; i++) out[i] = buttons[i] && buttons[i].pressed;
    out[11] = stick(g.leftThumbstick.xAxis.value);  out[12] = stick(-g.leftThumbstick.yAxis.value);
    out[13] = trigger(g.leftTrigger.value);
    out[14] = stick(g.rightThumbstick.xAxis.value); out[15] = stick(-g.rightThumbstick.yAxis.value);
    out[16] = trigger(g.rightTrigger.value);
    out[17] = hat(g.dpad.up.pressed, g.dpad.right.pressed, g.dpad.down.pressed, g.dpad.left.pressed);
}

static BOOL device_matches(GLHIDDevice *d, NSArray *matching) {
    if (!matching) return YES;
    for (NSDictionary *m in matching) {
        BOOL ok = YES;
        for (NSString *k in m) {
            id want = m[k], have = d->props[k];
            if ([k isEqualToString:@"DeviceUsagePage"]) have = d->props[@"PrimaryUsagePage"];
            if ([k isEqualToString:@"DeviceUsage"]) have = d->props[@"PrimaryUsage"];
            if (!have || ![have isEqual:want]) { ok = NO; break; }
        }
        if (ok) return YES;
    }
    return NO;
}

// (on the manager's run loop: new and gone pads, then changed values)
static double g_open_at;
static int test_button(void) {
    static int usage = -1; static double at;
    if (usage < 0) { const char *e = getenv("GL_PAD_TEST"); usage = 0; if (e) sscanf(e, "%d@%lf", &usage, &at); }
    if (!usage || !g_open_at) return 0;
    double t = CFAbsoluteTimeGetCurrent() - g_open_at;
    if (t >= at && t < at + 0.3) { static int said; if (!said++) vxmac_log("GRID HID: test press of button usage %d at %.1f s", usage, t); return usage; }
    return 0;
}
static void tick(CFRunLoopTimerRef t, void *info) {
    GLHIDManager *m = (__bridge GLHIDManager *)info;
    if (!m->open) return;
    NSArray<GLHIDDevice *> *devs;
    @synchronized (g_lock) {
        NSArray<GCController *> *pads = GCController.controllers;
        for (GLHIDDevice *d in [g_devices copy]) if (!d->pad || ![pads containsObject:d->pad]) [g_devices removeObject:d];
        int index = 0;
        for (GCController *c in pads) {
            if (!c.extendedGamepad) continue;
            BOOL known = NO;
            for (GLHIDDevice *d in g_devices) if (d->pad == c) known = YES;
            if (!known) {
                [g_devices addObject:make_device(c, index)];
                char msg[200]; snprintf(msg, sizeof msg, "HID: virtual Xbox 360 pad for \"%s\"", c.vendorName.UTF8String ?: "controller");
                vxmac_log("GRID %s", msg);
            }
            index++;
        }
        devs = [g_devices copy];
    }
    for (GLHIDDevice *d in [m->announced copy])
        if (![devs containsObject:d]) {
            [m->announced removeObject:d];
            if (m->remove_cb) m->remove_cb(m->remove_ctx, 0, (__bridge void *)m, (__bridge void *)d);
        }
    for (GLHIDDevice *d in devs)
        if (![m->announced containsObject:d] && device_matches(d, m->matching)) {
            [m->announced addObject:d];
            if (m->match_cb) m->match_cb(m->match_ctx, 0, (__bridge void *)m, (__bridge void *)d);
        }
    uint64_t now = mach_absolute_time();
    for (GLHIDDevice *d in m->announced) {
        GCController *c = d->pad;
        if (!c) continue;
        int64_t s[18]; read_pad(c, s);
        int tb = test_button(); if (tb >= 1 && tb <= 11) s[tb - 1] = 1;
        {   // (minimum press time: a release within it is held back until it has passed)
            static double min_s = -1;
            if (min_s < 0) { const char *e = getenv("GL_PAD_MIN_PRESS_MS"); min_s = (e && *e ? atof(e) : 100) / 1000.0; }
            double tn = CFAbsoluteTimeGetCurrent();
            for (int i = 0; i < 11; i++) {
                int64_t was = atomic_load(&d->elements[i]->value);
                if (s[i] && !was) d->pressed_at[i] = tn;
                else if (!s[i] && was && tn - d->pressed_at[i] < min_s) s[i] = 1;
            }
        }
        static int pad_log = -1; if (pad_log < 0) { const char *e = getenv("GL_PAD_LOG"); pad_log = e && !strcmp(e, "1"); }
        if (pad_log) {   // (GL_PAD_LOG=1: the first 200 button and hat changes the pad reports, as GameController gave them)
            static int logged; static int64_t prev[18];
            for (int i = 0; i < 18 && logged < 200; i++)
                if ((i < 11 || i == 17) && s[i] != prev[i]) { vxmac_log("GRID HID: %.3f pad %s %d -> %lld", CFAbsoluteTimeGetCurrent() - g_open_at, i == 17 ? "hat" : "button", i == 17 ? 0 : i + 1, (long long)s[i]); logged++; }
            memcpy(prev, s, sizeof prev);
        }
        for (int i = 0; i < 18 && i < (int)d->elements.count; i++) {
            GLHIDElement *e = d->elements[i];
            if (atomic_exchange(&e->value, s[i]) == s[i]) continue;
            atomic_store(&e->stamp, now);
            if (m->value_cb_) {
                GLHIDValue *v = [GLHIDValue new]; v->elem = e; v->value = s[i]; v->stamp = now;
                m->value_cb_(m->value_ctx, 0, (__bridge void *)d, (__bridge void *)v);
            }
        }
    }
}

static void start_timer(GLHIDManager *m) {
    if (m->timer || !m->runloop) return;
    CFRunLoopTimerContext ctx = { 0, (__bridge void *)m, NULL, NULL, NULL };
    m->timer = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent() + 0.004, 0.004, 0, 0, tick, &ctx);
    CFRunLoopAddTimer(m->runloop, m->timer, m->mode ?: kCFRunLoopDefaultMode);
}

__attribute__((constructor)) static void glhid_init(void) {
    g_devices = [NSMutableArray array]; g_managers = [NSMutableArray array]; g_lock = [NSObject new];
}

// ---- IOHIDManager -------------------------------------------------------------------------------------------------------
void *IOHIDManagerCreate(CFAllocatorRef a, uint32_t opts) {
    L("IOHIDManagerCreate -> virtual manager");
    GLHIDManager *m = [GLHIDManager new];
    m->announced = [NSMutableArray array];
    @synchronized (g_lock) { [g_managers addObject:m]; }
    return (void *)CFBridgingRetain(m);
}
void IOHIDManagerSetDeviceMatching(void *mgr, CFDictionaryRef match) {
    L("IOHIDManagerSetDeviceMatching");
    ((__bridge GLHIDManager *)mgr)->matching = match ? @[ (__bridge NSDictionary *)match ] : nil;
}
void IOHIDManagerSetDeviceMatchingMultiple(void *mgr, CFArrayRef multiple) {
    L("IOHIDManagerSetDeviceMatchingMultiple");
    ((__bridge GLHIDManager *)mgr)->matching = multiple ? [(__bridge NSArray *)multiple copy] : nil;
}
void IOHIDManagerSetInputValueMatchingMultiple(void *mgr, CFArrayRef multiple) { L("IOHIDManagerSetInputValueMatchingMultiple (all values delivered)"); }
void IOHIDManagerRegisterDeviceMatchingCallback(void *mgr, device_cb cb, void *ctx) {
    L("IOHIDManagerRegisterDeviceMatchingCallback");
    GLHIDManager *m = (__bridge GLHIDManager *)mgr; m->match_cb = cb; m->match_ctx = ctx;
}
void IOHIDManagerRegisterDeviceRemovalCallback(void *mgr, device_cb cb, void *ctx) {
    L("IOHIDManagerRegisterDeviceRemovalCallback");
    GLHIDManager *m = (__bridge GLHIDManager *)mgr; m->remove_cb = cb; m->remove_ctx = ctx;
}
void IOHIDManagerRegisterInputValueCallback(void *mgr, value_cb cb, void *ctx) {
    L("IOHIDManagerRegisterInputValueCallback");
    GLHIDManager *m = (__bridge GLHIDManager *)mgr; m->value_cb_ = cb; m->value_ctx = ctx;
}
void IOHIDManagerScheduleWithRunLoop(void *mgr, CFRunLoopRef rl, CFStringRef mode) {
    L("IOHIDManagerScheduleWithRunLoop");
    GLHIDManager *m = (__bridge GLHIDManager *)mgr; m->runloop = rl; m->mode = mode ? CFStringCreateCopy(NULL, mode) : NULL;
    if (m->open) start_timer(m);
}
void IOHIDManagerUnscheduleFromRunLoop(void *mgr, CFRunLoopRef rl, CFStringRef mode) {
    L("IOHIDManagerUnscheduleFromRunLoop");
    GLHIDManager *m = (__bridge GLHIDManager *)mgr;
    if (m->timer) { CFRunLoopTimerInvalidate(m->timer); CFRelease(m->timer); m->timer = NULL; }
    m->runloop = NULL;
}
IOReturn_ IOHIDManagerOpen(void *mgr, uint32_t opts) {
    L("IOHIDManagerOpen");
    GLHIDManager *m = (__bridge GLHIDManager *)mgr; m->open = YES; start_timer(m);
    if (!g_open_at) g_open_at = CFAbsoluteTimeGetCurrent();
    return kIOReturnSuccess_;
}
IOReturn_ IOHIDManagerClose(void *mgr, uint32_t opts) {
    L("IOHIDManagerClose");
    ((__bridge GLHIDManager *)mgr)->open = NO;
    return kIOReturnSuccess_;
}
CFSetRef IOHIDManagerCopyDevices(void *mgr) {
    L("IOHIDManagerCopyDevices");
    GLHIDManager *m = (__bridge GLHIDManager *)mgr;
    NSMutableSet *s = [NSMutableSet set];
    @synchronized (g_lock) { for (GLHIDDevice *d in g_devices) if (device_matches(d, m->matching)) [s addObject:d]; }
    return s.count ? (CFSetRef)CFBridgingRetain(s) : NULL;
}

// ---- IOHIDDevice ---------------------------------------------------------------------------------------------------------
CFTypeRef IOHIDDeviceGetProperty(void *dev, CFStringRef key) {
    L("IOHIDDeviceGetProperty");
    return (__bridge CFTypeRef)((__bridge GLHIDDevice *)dev)->props[(__bridge NSString *)key];
}
CFArrayRef IOHIDDeviceCopyMatchingElements(void *dev, CFDictionaryRef match, uint32_t opts) {
    L("IOHIDDeviceCopyMatchingElements");
    GLHIDDevice *d = (__bridge GLHIDDevice *)dev;
    NSDictionary *m = (__bridge NSDictionary *)match;
    NSMutableArray *out = [NSMutableArray array];
    for (GLHIDElement *e in d->elements) {
        if (m[@"UsagePage"] && [m[@"UsagePage"] unsignedIntValue] != e->page) continue;
        if (m[@"Usage"] && [m[@"Usage"] unsignedIntValue] != e->usage) continue;
        if (m[@"Type"] && [m[@"Type"] unsignedIntValue] != e->type) continue;
        if (m[@"ElementCookie"] && [m[@"ElementCookie"] unsignedIntValue] != e->cookie) continue;
        [out addObject:e];
    }
    return (CFArrayRef)CFBridgingRetain(out);
}
IOReturn_ IOHIDDeviceGetValue(void *dev, void *elem, void **out) {
    gl_log_once("HID: IOHIDDeviceGetValue (polled)");
    GLHIDElement *e = (__bridge GLHIDElement *)elem;
    GLHIDDevice *d = (__bridge GLHIDDevice *)dev;
    uint32_t i = e->cookie - 1;
    if (i >= 32) return kIOReturnNotFound_;
    // (a Get function: the value is owned by the device and stays valid until the next call for that element)
    GLHIDValue *v = d->latest[i];
    if (!v) { v = [GLHIDValue new]; v->elem = e; d->latest[i] = v; }
    v->value = atomic_load(&e->value); v->stamp = atomic_load(&e->stamp);
    if (out) *out = (__bridge void *)v;
    return kIOReturnSuccess_;
}
IOReturn_ IOHIDDeviceSetValue(void *dev, void *elem, void *value) { L("IOHIDDeviceSetValue (ignored)"); return kIOReturnSuccess_; }
IOReturn_ IOHIDDeviceSetReport(void *dev, uint32_t type, CFIndex id, const uint8_t *r, CFIndex len) { L("IOHIDDeviceSetReport (ignored: rumble, lights)"); return kIOReturnSuccess_; }
IOReturn_ IOHIDDeviceGetReport(void *dev, uint32_t type, CFIndex id, uint8_t *r, CFIndex *len) { L("IOHIDDeviceGetReport -> unsupported"); if (len) *len = 0; return kIOReturnUnsupported_; }
void IOHIDDeviceRegisterInputReportCallback(void *dev, uint8_t *buf, CFIndex len, void *cb, void *ctx) { L("IOHIDDeviceRegisterInputReportCallback (raw reports: none)"); }
uint32_t IOHIDDeviceGetService(void *dev) { L("IOHIDDeviceGetService -> none"); return 0; }

// ---- IOHIDElement ----------------------------------------------------------------------------------------------------------
#define E ((__bridge GLHIDElement *)elem)
uint32_t IOHIDElementGetCookie(void *elem) { return E->cookie; }
uint32_t IOHIDElementGetType(void *elem) { return E->type; }
uint32_t IOHIDElementGetUsagePage(void *elem) { return E->page; }
uint32_t IOHIDElementGetUsage(void *elem) { return E->usage; }
CFIndex IOHIDElementGetLogicalMin(void *elem) { return E->lmin; }
CFIndex IOHIDElementGetLogicalMax(void *elem) { return E->lmax; }
CFIndex IOHIDElementGetPhysicalMin(void *elem) { return E->pmin; }
CFIndex IOHIDElementGetPhysicalMax(void *elem) { return E->pmax; }
uint32_t IOHIDElementGetReportCount(void *elem) { return 1; }
uint32_t IOHIDElementGetReportID(void *elem) { return 0; }
void *IOHIDElementGetDevice(void *elem) { return (__bridge void *)E->dev; }
#undef E

// ---- IOHIDValue ------------------------------------------------------------------------------------------------------------
#define V ((__bridge GLHIDValue *)val)
void *IOHIDValueGetElement(void *val) { return (__bridge void *)V->elem; }
CFIndex IOHIDValueGetIntegerValue(void *val) { return (CFIndex)V->value; }
uint64_t IOHIDValueGetTimeStamp(void *val) { return V->stamp; }
CFIndex IOHIDValueGetLength(void *val) { return 4; }
const uint8_t *IOHIDValueGetBytePtr(void *val) { int32_t x = (int32_t)V->value; memcpy(V->bytes, &x, 4); return V->bytes; }
double IOHIDValueGetScaledValue(void *val, uint32_t type) {
    GLHIDElement *e = V->elem;
    double lo = e->lmin, hi = e->lmax, x = (double)V->value;
    if (hi <= lo) return x;
    double t = (x - lo) / (hi - lo);
    if (type == 0) return -1.0 + 2.0 * t;          // (kIOHIDValueScaleTypeCalibrated: -1..1)
    return e->pmin + t * (e->pmax - e->pmin);      // (physical)
}
void *IOHIDValueCreateWithBytes(CFAllocatorRef a, void *elem, uint64_t stamp, const uint8_t *bytes, CFIndex len) {
    GLHIDValue *v = [GLHIDValue new];
    v->elem = (__bridge GLHIDElement *)elem; v->stamp = stamp;
    int64_t x = 0; memcpy(&x, bytes, len < 8 ? (size_t)len : 8); v->value = x;
    return (void *)CFBridgingRetain(v);
}
#undef V
