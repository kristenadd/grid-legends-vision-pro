// libglcg: CoreGraphics for GRID Legends. Re-exports libvxcg (VXpro: CoreGraphics + the CGDisplay calls) and adds the
// rest the game imports: synthetic events (inert), gamma tables (identity), display lists, window lists (empty).
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdint.h>
#include "glcommon.h"

typedef uint32_t DisplayID;
typedef int32_t CGErr;

// ---- displays ----
CGErr CGGetOnlineDisplayList(uint32_t max, DisplayID *ids, uint32_t *count) {
    if (ids && max > 0) ids[0] = 1;            // (libvxcg's CGMainDisplayID)
    if (count) *count = (ids && max == 0) ? 0 : 1;
    return 0;
}
CGSize CGDisplayScreenSize(DisplayID d) { (void)d; return CGSizeMake(600.0, 337.5); }   // (millimetres, 16:9)
CGErr CGDisplayRegisterReconfigurationCallback(void *cb, void *ctx) { (void)cb; (void)ctx; return 0; }
CGErr CGDisplayRemoveReconfigurationCallback(void *cb, void *ctx) { (void)cb; (void)ctx; return 0; }
uint32_t CGDisplayGammaTableCapacity(DisplayID d) { (void)d; return 256; }
CGErr CGGetDisplayTransferByTable(DisplayID d, uint32_t cap, float *r, float *g, float *b, uint32_t *count) {
    (void)d;
    for (uint32_t i = 0; i < cap; i++) { float v = cap > 1 ? (float)i / (float)(cap - 1) : 0.f; r[i] = g[i] = b[i] = v; }
    if (count) *count = cap;
    return 0;
}
CGErr CGSetDisplayTransferByTable(DisplayID d, uint32_t n, const float *r, const float *g, const float *b) {
    (void)d; (void)n; (void)r; (void)g; (void)b;
    gl_log_once("CoreGraphics: CGSetDisplayTransferByTable ignored (no gamma control)");
    return 0;
}

// The Metal device of the display: the system's default device, +1 (a "Copy" function).
extern void *MTLCreateSystemDefaultDevice(void);
void *CGDirectDisplayCopyCurrentMetalDevice(DisplayID d) { (void)d; return MTLCreateSystemDefaultDevice(); }

// ---- synthetic events: real CF objects (so CFRelease works) that do nothing ----
static CFTypeRef new_event(void) { return CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks); }
CFTypeRef CGEventCreate(void *src) { (void)src; return new_event(); }
CFTypeRef CGEventCreateKeyboardEvent(void *src, uint16_t key, bool down) { (void)src; (void)key; (void)down; return new_event(); }
CFTypeRef CGEventCreateMouseEvent(void *src, uint32_t type, CGPoint p, uint32_t button) { (void)src; (void)type; (void)p; (void)button; return new_event(); }
CFTypeRef CGEventCreateScrollWheelEvent(void *src, uint32_t units, uint32_t count, int32_t w1, ...) { (void)src; (void)units; (void)count; (void)w1; return new_event(); }
void CGEventPost(uint32_t tap, CFTypeRef e) { (void)tap; (void)e; gl_log_once("CoreGraphics: CGEventPost ignored"); }
uint64_t CGEventGetFlags(CFTypeRef e) { (void)e; return 0; }
void CGEventSetFlags(CFTypeRef e, uint64_t f) { (void)e; (void)f; }
CGPoint CGEventGetLocation(CFTypeRef e) { (void)e; return CGPointZero; }
void CGEventSetIntegerValueField(CFTypeRef e, uint32_t field, int64_t v) { (void)e; (void)field; (void)v; }
bool CGEventSourceKeyState(int32_t state, uint16_t key) { (void)state; (void)key; return false; }
CGErr CGSetLocalEventsSuppressionInterval(double s) { (void)s; return 0; }

// ---- window lists: no other windows ----
CFArrayRef CGWindowListCopyWindowInfo(uint32_t opt, uint32_t rel) { (void)opt; (void)rel; return CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks); }
CGImageRef CGWindowListCreateImage(CGRect r, uint32_t opt, uint32_t win, uint32_t img) { (void)r; (void)opt; (void)win; (void)img; return NULL; }
