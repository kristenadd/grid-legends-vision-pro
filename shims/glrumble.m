// glrumble.m (in libgliokit): the virtual pad's rumble, played on the GameController pad's haptics.
//
// How the game rumbles a HID pad on the Mac (its code at 0x100c32354-0x100c33900, read from GRIDLegends.dylib):
//   1. it asks IOKit for the pad's service: IOServiceGetMatchingService(IOServiceMatching("IOHIDDevice") + LocationID
//      from IOHIDDeviceGetProperty). The real IOKit has no such device, so here a virtual pad's LocationID gives a
//      stand-in service number (gl_rumble_service);
//   2. FFIsForceFeedback(service) and FFCreateDevice(service) (libglff forwards to the gl_ff_* functions below);
//   3. per change of the two motor levels (0-65535, the big low-frequency one and the small high-frequency one):
//      an Xbox 360 pad gets FFDeviceEscape, the Mac 360 driver's motor command: two bytes, left (big) and right (small),
//      0-255 (after a one-off command with one byte, 1); other pads get ForceFeedback effects (logged here, not played).
// Step 2 never happens by itself: the game's CGPHIDDevice::InitFFB (0x100c32614) does not do it, it queues a lambda
// (0x100c33838) on the main-thread scheduler 1,000,000 s (11.6 days) ahead, and SetRumble does nothing until that has set
// the FF device (+0x270). So the pads' vtables get InitFFB swapped for one that calls the game's own InitFFB and then
// that lambda at once (gl_rumble_patch: in memory, only where the code at those addresses is exactly what was read).
// Played with CoreHaptics on the pad's haptics: the big motor on the left handle, the small one on the right (one engine
// with the larger of the two if the pad has no handles), each a looping continuous event whose intensity follows the
// motor. GL_RUMBLE=0 turns it off; GL_RUMBLE_SCALE (default 1.0) scales it; GL_RUMBLE_LOG=1 logs the first 200 changes.
#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import <CoreHaptics/CoreHaptics.h>
#include <stdlib.h>
#include <string.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach/mach.h>
#include "glcommon.h"

GCController *gl_hid_pad_for_location(long location);   // (glhid.m)

enum { kServiceBase = 0x47520000 };
static const int32_t FF_OK = 0, FFERR_NOINTERFACE = (int32_t)0x80004002, FFERR_UNSUPPORTED = (int32_t)0x80004001;

static dispatch_queue_t q(void) {
    static dispatch_queue_t s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = dispatch_queue_create("gl.rumble", DISPATCH_QUEUE_SERIAL); });
    return s;
}
static int enabled(void) { static int v = -1; if (v < 0) { const char *e = getenv("GL_RUMBLE"); v = !(e && !strcmp(e, "0")); } return v; }
static float scale(void) { static float v = -1; if (v < 0) { const char *e = getenv("GL_RUMBLE_SCALE"); v = e && *e ? (float)atof(e) : 1.f; } return v; }
static int logging(void) { static int v = -1; if (v < 0) { const char *e = getenv("GL_RUMBLE_LOG"); v = e && !strcmp(e, "1"); } return v; }

// ---- a motor: one haptic engine with a looping continuous event --------------------------------------------------------
// (the pad's haptics service can refuse at first - "Couldn't communicate with a helper application" - so a failure drops
//  the engine and it is made again a second later, up to 20 times)
@interface GLMotor : NSObject {
@public
    __weak GCController *pad; GCHapticsLocality locality;
    CHHapticEngine *engine; id<CHHapticAdvancedPatternPlayer> player; float sharpness, level; BOOL playing, simple, started, ticking; int failures, simple_failures; double retry_at;
}
@end
@implementation GLMotor @end

static double now_s(void) { return CFAbsoluteTimeGetCurrent(); }
static void motor_fail(GLMotor *m, const char *what, NSError *err) {
    m->engine = nil; m->player = nil; m->playing = NO;
    m->failures++; m->retry_at = now_s() + 1.0;
    if (m->failures <= 3 || m->failures == 20)
        vxmac_log("GRID rumble: %s (%s, try %d%s)", what, err.localizedDescription.UTF8String ?: "no reason", m->failures, m->failures >= 20 ? ": giving up" : "");
}
static BOOL motor_engine(GLMotor *m) {
    if (m->engine) return YES;
    if (m->failures >= 20 || now_s() < m->retry_at) return NO;
    GCController *c = m->pad;
    m->engine = c ? [c.haptics createEngineWithLocality:m->locality] : nil;
    if (!m->engine) { motor_fail(m, "no haptic engine", nil); return NO; }
    m->engine.playsHapticsOnly = YES;
    __weak GLMotor *wm = m;
    m->engine.resetHandler = ^{ dispatch_async(q(), ^{ GLMotor *s = wm; if (s) { s->player = nil; s->playing = NO; s->started = NO; } }); };
    m->engine.stoppedHandler = ^(CHHapticEngineStoppedReason r) { (void)r; dispatch_async(q(), ^{ GLMotor *s = wm; if (s) { s->player = nil; s->playing = NO; s->started = NO; } }); };
    return YES;
}
static GLMotor *motor(GCController *c, GCHapticsLocality loc, float sharpness) {
    GLMotor *m = [GLMotor new];
    m->pad = c; m->locality = loc; m->sharpness = sharpness;
    motor_engine(m);
    return m;
}
// (the simple way, when the system won't make a looping player: a 0.15 s continuous event at the level, every 0.1 s while
//  the level is up)
static void motor_tick(GLMotor *m) {   // (on q())
    if (!m->engine || m->level <= 0.002f || !m->simple) { m->ticking = NO; return; }
    NSError *err = nil;
    if (!m->started) {
        if (![m->engine startAndReturnError:&err]) { motor_fail(m, "haptic engine did not start", err); m->started = NO; m->ticking = NO; return; }
        m->started = YES;
    }
    CHHapticEvent *ev = [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticContinuous parameters:@[
        [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity value:m->level],
        [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness value:m->sharpness]]
        relativeTime:0 duration:0.15];
    CHHapticPattern *p = [[CHHapticPattern alloc] initWithEvents:@[ev] parameters:@[] error:&err];
    id<CHHapticPatternPlayer> pl = p ? [m->engine createPlayerWithPattern:p error:&err] : nil;
    if (!pl || ![pl startAtTime:CHHapticTimeImmediate error:&err]) {
        m->simple_failures++;
        if (m->simple_failures <= 3) vxmac_log("GRID rumble: no simple haptic player either (%s, try %d)", err.localizedDescription.UTF8String ?: "no reason", m->simple_failures);
        m->started = NO;
        if (m->simple_failures >= 20) { m->ticking = NO; return; }
    } else if (m->simple_failures >= 0) {
        vxmac_log("GRID rumble: haptics playing (short events at the game's level)");
        m->simple_failures = -1000000;
    }
    __weak GLMotor *wm = m;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), q(), ^{ GLMotor *s = wm; if (s) motor_tick(s); });
}
static void motor_set(GLMotor *m, float level) {   // (on q())
    if (!m) return;
    m->level = level;
    NSError *err = nil;
    if (m->simple) { if (level > 0.002f && !m->ticking && m->engine) { m->ticking = YES; motor_tick(m); } return; }
    if (level <= 0.002f) {
        if (m->playing) { [m->player stopAtTime:CHHapticTimeImmediate error:nil]; m->playing = NO; }
        return;
    }
    if (!motor_engine(m)) {
        if (m->failures >= 3) {   // (the looping player keeps failing: the simple way, with a fresh engine)
            m->simple = YES; m->failures = 0; m->retry_at = 0;
            vxmac_log("GRID rumble: no looping haptic player: short events instead");
            if (motor_engine(m)) { m->ticking = YES; motor_tick(m); }
        }
        return;
    }
    if (!m->player) {
        if (![m->engine startAndReturnError:&err]) { motor_fail(m, "haptic engine did not start", err); return; }
        CHHapticEvent *ev = [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticContinuous parameters:@[
            [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity value:1.0],
            [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness value:m->sharpness]]
            relativeTime:0 duration:30];
        CHHapticPattern *p = [[CHHapticPattern alloc] initWithEvents:@[ev] parameters:@[] error:&err];
        m->player = p ? [m->engine createAdvancedPlayerWithPattern:p error:&err] : nil;
        if (!m->player) { motor_fail(m, "no haptic player", err); return; }
        m->player.loopEnabled = YES;
        if (m->failures) { vxmac_log("GRID rumble: haptics working after %d tr%s", m->failures, m->failures == 1 ? "y" : "ies"); m->failures = 0; }
    }
    CHHapticDynamicParameter *dp = [[CHHapticDynamicParameter alloc] initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl value:level relativeTime:0];
    [m->player sendParameters:@[dp] atTime:CHHapticTimeImmediate error:nil];
    if (!m->playing) {
        m->playing = [m->player startAtTime:CHHapticTimeImmediate error:&err];
        if (!m->playing) motor_fail(m, "haptic player did not start", err);
    }
}

// ---- the ForceFeedback device: one per pad -------------------------------------------------------------------------------
@interface GLFFDevice : NSObject {
@public
    long location; __weak GCController *pad; GLMotor *big, *small, *both; BOOL made; float lo, hi;
}
@end
@implementation GLFFDevice @end

static void play(GLFFDevice *d, float lo, float hi) {
    if (!enabled()) return;
    float s = scale();
    lo = fminf(1, lo * s); hi = fminf(1, hi * s);
    dispatch_async(q(), ^{
        if (fabsf(lo - d->lo) < 0.004f && fabsf(hi - d->hi) < 0.004f) return;
        d->lo = lo; d->hi = hi;
        static int n;
        if (logging() && n < 200) { n++; vxmac_log("GRID rumble: big %.2f small %.2f", lo, hi); }
        GCController *c = d->pad ?: gl_hid_pad_for_location(d->location);
        if (!c) return;
        if (!d->made) {
            d->made = YES; d->pad = c;
            NSSet *locs = c.haptics.supportedLocalities;
            if (!c.haptics) vxmac_log("GRID rumble: \"%s\" has no haptics", c.vendorName.UTF8String);
            else if ([locs containsObject:GCHapticsLocalityLeftHandle] && [locs containsObject:GCHapticsLocalityRightHandle]) {
                d->big = motor(c, GCHapticsLocalityLeftHandle, 0.2f); d->small = motor(c, GCHapticsLocalityRightHandle, 0.7f);
                vxmac_log("GRID rumble: on \"%s\": big motor left handle, small motor right handle", c.vendorName.UTF8String);
            } else {
                d->both = motor(c, GCHapticsLocalityDefault, 0.4f);
                vxmac_log("GRID rumble: on \"%s\": one engine (no separate handles)", c.vendorName.UTF8String);
            }
        }
        if (d->both) motor_set(d->both, fmaxf(lo, hi));
        else { motor_set(d->big, lo); motor_set(d->small, hi); }
    });
}

// ---- the game's rumble setup, run now instead of in 11.6 days ---------------------------------------------------------------
static const uintptr_t kInitFFB = 0x100c32614, kInitLambda = 0x100c33838, kSetRumble = 0x100c32b90;   // (file addresses)
static void (*g_init_ffb)(void *self), (*g_init_lambda)(void *closure);
static void init_ffb_now(void *self) {
    g_init_ffb(self);                          // (queues the lambda far ahead, the motors to 0)
    struct { void *vtable, *self; } closure = { NULL, self };
    g_init_lambda(&closure);                   // (+0x270 = FFCreateDevice(the service at +0x278), the motors to 0)
    gl_log_once("rumble: the game's rumble setup for a HID pad run now (it queues it 11.6 days ahead)");
}
static void gl_rumble_patch(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!enabled()) return;
        const char *want = getenv("GL_GAME_IMAGE"); if (!want || !*want) want = "GRIDLegends.dylib";
        const struct mach_header_64 *h = NULL; intptr_t slide = 0;
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            const char *n = _dyld_get_image_name(i), *b = strrchr(n, '/');
            if (!strcmp(b ? b + 1 : n, want)) { h = (const struct mach_header_64 *)_dyld_get_image_header(i); slide = _dyld_get_image_vmaddr_slide(i); break; }
        }
        if (!h) { vxmac_log("GRID rumble: the game image is not loaded: no rumble"); return; }
        // (this game's code at the three addresses, as read from GRIDLegends.dylib; another build: no patch)
        static const uint32_t want_init[] = { 0xd101c3ff, 0xa9054ff4, 0xa9067bfd, 0x910183fd },
                              want_lambda[] = { 0xa9be4ff4, 0xa9017bfd, 0x910043fd, 0xf9400413 },
                              want_set[] = { 0xd10243ff, 0xa90467fa, 0xa9055ff8, 0xa90657f6 };
        uintptr_t init = kInitFFB + slide, lambda = kInitLambda + slide, set = kSetRumble + slide;
        if (memcmp((void *)init, want_init, 16) || memcmp((void *)lambda, want_lambda, 16) || memcmp((void *)set, want_set, 16)) {
            vxmac_log("GRID rumble: the game's rumble code is not where it was read (another build?): no rumble"); return;
        }
        g_init_ffb = (void (*)(void *))init; g_init_lambda = (void (*)(void *))lambda;
        uintptr_t text0 = 0, text1 = 0;
        const struct load_command *lc = (const void *)(h + 1);
        for (uint32_t i = 0; i < h->ncmds; i++, lc = (const void *)((const char *)lc + lc->cmdsize)) {
            if (lc->cmd != LC_SEGMENT_64) continue;
            const struct segment_command_64 *sg = (const void *)lc;
            if (!strcmp(sg->segname, "__TEXT")) { text0 = sg->vmaddr + slide; text1 = text0 + sg->vmsize; }
        }
        int patched = 0;
        lc = (const void *)(h + 1);
        for (uint32_t i = 0; i < h->ncmds; i++, lc = (const void *)((const char *)lc + lc->cmdsize)) {
            if (lc->cmd != LC_SEGMENT_64) continue;
            const struct segment_command_64 *sg = (const void *)lc;
            if (strcmp(sg->segname, "__DATA_CONST") && strcmp(sg->segname, "__DATA")) continue;
            uintptr_t *p = (uintptr_t *)(sg->vmaddr + slide), *end = (uintptr_t *)(sg->vmaddr + slide + sg->vmsize) - 9;
            for (; p < end; p++) {
                if (*p != init) continue;
                uintptr_t sr = p[(0xc8 - 0x80) / 8];     // (a vtable: its SetRumble slot points into the game's code)
                if (sr < text0 || sr >= text1) continue;
                vm_address_t page = (vm_address_t)p & ~(vm_address_t)(vm_page_size - 1);
                if (vm_protect(mach_task_self(), page, vm_page_size, FALSE, VM_PROT_READ | VM_PROT_WRITE) != KERN_SUCCESS) {
                    vxmac_log("GRID rumble: a vtable is not writable: no rumble"); continue;
                }
                *p = (uintptr_t)init_ffb_now;
                if (!strcmp(sg->segname, "__DATA_CONST")) vm_protect(mach_task_self(), page, vm_page_size, FALSE, VM_PROT_READ);
                patched++;
            }
        }
        vxmac_log("GRID rumble: InitFFB swapped in %d vtable%s (HID pads: the rumble setup runs at once)", patched, patched == 1 ? "" : "s");
    });
}

// ---- IOKit: the pad's service ------------------------------------------------------------------------------------------------
// (matching = IOServiceMatching("IOHIDDevice") with LocationID: a virtual pad's stand-in service, else 0)
uint32_t gl_rumble_service(CFDictionaryRef matching) {
    if (!matching || CFGetTypeID(matching) != CFDictionaryGetTypeID()) return 0;
    NSDictionary *m = (__bridge NSDictionary *)matching;
    id cls = m[@"IOProviderClass"], loc = m[@"LocationID"];
    if (![cls isEqual:@"IOHIDDevice"] || ![loc isKindOfClass:[NSNumber class]]) return 0;
    if (!gl_hid_pad_for_location([loc longValue])) return 0;
    gl_rumble_patch();   // (before the game sets the pad up: the service is looked up when the device is made)
    gl_log_once("rumble: the game found the virtual pad's service (LocationID)");
    return kServiceBase + (uint32_t)([loc longValue] & 0xffff);
}
int gl_rumble_is_service(uint32_t s) { return (s & 0xffff0000) == kServiceBase; }

// ---- ForceFeedback (libglff forwards here) ---------------------------------------------------------------------------------
int32_t gl_ff_is(uint32_t service) {
    if (!gl_rumble_is_service(service)) return FFERR_NOINTERFACE;
    gl_log_once("rumble: FFIsForceFeedback -> yes (virtual pad)");
    return FF_OK;
}
int32_t gl_ff_create(uint32_t service, void **out) {
    if (out) *out = NULL;
    if (!gl_rumble_is_service(service) || !out) return FFERR_NOINTERFACE;
    GLFFDevice *d = [GLFFDevice new];
    d->location = 0x14100000 + (service & 0xffff);
    *out = (void *)CFBridgingRetain(d);
    gl_log_once("rumble: FFCreateDevice -> a device for the virtual pad");
    return FF_OK;
}
int32_t gl_ff_release(void *dev) {
    if (!dev) return FF_OK;
    GLFFDevice *d = (GLFFDevice *)CFBridgingRelease(dev);
    play(d, 0, 0);
    return FF_OK;
}
typedef struct { uint32_t size, command; void *in; uint32_t in_size; void *out; uint32_t out_size; } ff_escape;
int32_t gl_ff_escape(void *dev, void *escp) {
    if (!dev || !escp) return FFERR_UNSUPPORTED;
    GLFFDevice *d = (__bridge GLFFDevice *)dev;
    const ff_escape *e = escp;
    static uint32_t seen[8]; static int nseen;
    int known = 0; for (int i = 0; i < nseen; i++) known |= seen[i] == e->command;
    if (!known && nseen < 8) { seen[nseen++] = e->command; vxmac_log("GRID rumble: FFDeviceEscape command %u, %u bytes in", e->command, e->in_size); }
    if (e->in && e->in_size == 2) {   // (the 360 driver's motors: left (big), right (small), 0-255)
        const uint8_t *b = e->in;
        play(d, b[0] / 255.f, b[1] / 255.f);
    }
    return FF_OK;
}
int32_t gl_ff_unsupported(const char *what) {   // (the effect calls: logged once each)
    static NSMutableSet *seen; static dispatch_once_t once; dispatch_once(&once, ^{ seen = [NSMutableSet set]; });
    @synchronized (seen) { NSString *s = @(what); if (![seen containsObject:s]) { [seen addObject:s]; vxmac_log("GRID rumble: %s (not played)", what); } }
    return FFERR_UNSUPPORTED;
}
