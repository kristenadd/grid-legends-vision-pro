// libglmtl: Metal for GRID Legends. Re-exports libvxmtl (VXpro's Metal: present hook, pacing, macOS-only methods made
// no-ops) and adds:
// - the three macOS device notification names;
// - MTLStorageModeManaged (macOS only; visionOS's Metal refuses it) as Shared: on Apple silicon's unified memory a
//   managed resource is one shared copy anyway, and its didModifyRange: / synchronizeResource: are no-ops (libvxmtl).
//   Depth and stencil textures, which cannot be shared, become Private.
// - setPurgeableState: on textures, buffers and heaps, counted (logged every 5 s when anything changed): how many calls
//   per state, how often the system had already discarded the contents (Empty returned), the bytes marked volatile.
//   Feral marks cached resources volatile; under the headset's memory pressure the system may discard them, and the
//   game reloads them (a texture blinking?). GL_NO_VOLATILE=1 keeps them non-volatile instead (nothing discarded; the
//   memory then counts in the footprint).
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <TargetConditionals.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include "glcommon.h"

NSString *const MTLDeviceWasAddedNotification = @"MTLDeviceWasAddedNotification";
NSString *const MTLDeviceRemovalRequestedNotification = @"MTLDeviceRemovalRequestedNotification";
NSString *const MTLDeviceWasRemovedNotification = @"MTLDeviceWasRemovedNotification";

enum { kManaged = 1, kOptStorageShift = 4, kOptStorageMask = 0xF << 4 };

static BOOL is_depth_stencil(MTLPixelFormat f) {
    switch (f) {
    case MTLPixelFormatDepth16Unorm: case MTLPixelFormatDepth32Float: case MTLPixelFormatStencil8:
    case MTLPixelFormatDepth32Float_Stencil8: case MTLPixelFormatX32_Stencil8:
        return YES;
    default:
        return (NSUInteger)f == 255 || (NSUInteger)f == 260 || (NSUInteger)f == 262;   // (Depth24Unorm_Stencil8, X24_Stencil8: macOS)
    }
}
static NSUInteger fixed_mode(MTLTextureDescriptor *d) { return is_depth_stencil(d.pixelFormat) ? MTLStorageModePrivate : MTLStorageModeShared; }

// ---- texture descriptors ----
static IMP o_set_mode, o_set_opts;
static void h_set_mode(MTLTextureDescriptor *self, SEL s, NSUInteger m) {
    if (m == kManaged) { gl_log_once("Metal: managed texture storage -> shared (private for depth/stencil)"); m = fixed_mode(self); }
    ((void (*)(id, SEL, NSUInteger))o_set_mode)(self, s, m);
}
static void h_set_opts(MTLTextureDescriptor *self, SEL s, NSUInteger o) {
    if (((o & kOptStorageMask) >> kOptStorageShift) == kManaged) {
        gl_log_once("Metal: managed texture resource options -> shared (private for depth/stencil)");
        o = (o & ~(NSUInteger)kOptStorageMask) | (fixed_mode(self) << kOptStorageShift);
    }
    ((void (*)(id, SEL, NSUInteger))o_set_opts)(self, s, o);
}

// ---- buffers ----
static NSUInteger fix_buf_opts(NSUInteger o) {
    if (((o & kOptStorageMask) >> kOptStorageShift) == kManaged) {
        gl_log_once("Metal: managed buffer storage -> shared");
        o &= ~(NSUInteger)kOptStorageMask;   // (shared = 0)
    }
    return o;
}
typedef id (*buf_len_t)(id, SEL, NSUInteger, NSUInteger) __attribute__((ns_returns_retained));
typedef id (*buf_bytes_t)(id, SEL, const void *, NSUInteger, NSUInteger) __attribute__((ns_returns_retained));
typedef id (*buf_nocopy_t)(id, SEL, void *, NSUInteger, NSUInteger, id) __attribute__((ns_returns_retained));
static buf_len_t o_len; static buf_bytes_t o_bytes; static buf_nocopy_t o_nocopy;
__attribute__((ns_returns_retained)) static id h_len(id self, SEL s, NSUInteger n, NSUInteger o) { return o_len(self, s, n, fix_buf_opts(o)); }
__attribute__((ns_returns_retained)) static id h_bytes(id self, SEL s, const void *b, NSUInteger n, NSUInteger o) { return o_bytes(self, s, b, n, fix_buf_opts(o)); }
__attribute__((ns_returns_retained)) static id h_nocopy(id self, SEL s, void *b, NSUInteger n, NSUInteger o, id d) { return o_nocopy(self, s, b, n, fix_buf_opts(o), d); }

// ---- purgeable state ----
#include <stdatomic.h>
static _Atomic long g_purge_calls[5], g_purge_was_empty, g_volatile_bytes, g_purge_blocked;
static int no_volatile(void) { static int v = -1; if (v < 0) { const char *e = getenv("GL_NO_VOLATILE"); v = e && !strcmp(e, "1"); } return v; }
static NSUInteger res_size(id r) {
    if ([r respondsToSelector:@selector(allocatedSize)]) return ((NSUInteger (*)(id, SEL))objc_msgSend)(r, @selector(allocatedSize));
    return 0;
}
static MTLPurgeableState purge_common(id self, SEL s, MTLPurgeableState st, IMP orig) {
    if (st <= 4) atomic_fetch_add(&g_purge_calls[st], 1);
    if (no_volatile() && (st == MTLPurgeableStateVolatile || st == MTLPurgeableStateEmpty)) {
        atomic_fetch_add(&g_purge_blocked, 1);
        st = MTLPurgeableStateNonVolatile;
    }
    MTLPurgeableState old = ((MTLPurgeableState (*)(id, SEL, MTLPurgeableState))orig)(self, s, st);
    if (old == MTLPurgeableStateEmpty && st != MTLPurgeableStateKeepCurrent) atomic_fetch_add(&g_purge_was_empty, 1);
    if (st == MTLPurgeableStateVolatile && old != MTLPurgeableStateVolatile) atomic_fetch_add(&g_volatile_bytes, (long)res_size(self));
    if (st == MTLPurgeableStateNonVolatile && (old == MTLPurgeableStateVolatile || old == MTLPurgeableStateEmpty)) atomic_fetch_sub(&g_volatile_bytes, (long)res_size(self));
    return old;
}
static IMP o_purge_tex, o_purge_buf, o_purge_heap;
static MTLPurgeableState h_purge_tex(id self, SEL s, MTLPurgeableState st) { return purge_common(self, s, st, o_purge_tex); }
static MTLPurgeableState h_purge_buf(id self, SEL s, MTLPurgeableState st) { return purge_common(self, s, st, o_purge_buf); }
static MTLPurgeableState h_purge_heap(id self, SEL s, MTLPurgeableState st) { return purge_common(self, s, st, o_purge_heap); }
static void purge_report(void) {
    static long last[7];
    long now[7] = { g_purge_calls[1], g_purge_calls[2], g_purge_calls[3], g_purge_calls[4], g_purge_was_empty, g_purge_blocked, g_volatile_bytes >> 20 };
    if (!memcmp(now, last, sizeof now)) return;
    vxmac_log("GRID Metal: purgeable calls keep-current %ld non-volatile %ld volatile %ld empty %ld; found discarded %ld; volatile blocked %ld; volatile now %ld MB",
              now[0], now[1], now[2], now[3], now[4], now[5], now[6]);
    memcpy(last, now, sizeof now);
}

static void swap(Class c, SEL sel, IMP imp, IMP *orig) {
    Method m = class_getInstanceMethod(c, sel);
    if (!m) return;
    // (a subclass that inherits the method gets its own copy, so the superclass's stays as it was)
    if (class_addMethod(c, sel, imp, method_getTypeEncoding(m))) *orig = method_getImplementation(m);
    else *orig = method_setImplementation(m, imp);
}

__attribute__((constructor)) static void gl_mtl_init(void) {
    // (the descriptor the game allocates is MTLTextureDescriptor's concrete subclass; both are covered, each once)
    MTLTextureDescriptor *probe = [MTLTextureDescriptor new];
    Class concrete = [probe class], base = [MTLTextureDescriptor class];
    Class cls = concrete ?: base;
    swap(cls, @selector(setStorageMode:), (IMP)h_set_mode, &o_set_mode);
    swap(cls, @selector(setResourceOptions:), (IMP)h_set_opts, &o_set_opts);
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    if (dev) {
        Class dc = [dev class];
        swap(dc, @selector(newBufferWithLength:options:), (IMP)h_len, (IMP *)&o_len);
        swap(dc, @selector(newBufferWithBytes:length:options:), (IMP)h_bytes, (IMP *)&o_bytes);
        swap(dc, @selector(newBufferWithBytesNoCopy:length:options:deallocator:), (IMP)h_nocopy, (IMP *)&o_nocopy);
        // (the purgeable-state probes: the device's own texture, buffer and heap classes)
        id<MTLBuffer> pb = [dev newBufferWithLength:256 options:MTLResourceStorageModeShared];
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO];
        id<MTLTexture> pt = [dev newTextureWithDescriptor:td];
#if TARGET_OS_SIMULATOR
        id<MTLHeap> ph = nil;   // (the simulator's Metal asserts on heaps the device accepts)
#else
        MTLHeapDescriptor *hd = [MTLHeapDescriptor new]; hd.size = 1 << 16; hd.storageMode = MTLStorageModePrivate;
        id<MTLHeap> ph = [dev newHeapWithDescriptor:hd];
#endif
        if (pt) swap([pt class], @selector(setPurgeableState:), (IMP)h_purge_tex, &o_purge_tex);
        if (pb) swap([pb class], @selector(setPurgeableState:), (IMP)h_purge_buf, &o_purge_buf);
        if (ph) swap([ph class], @selector(setPurgeableState:), (IMP)h_purge_heap, &o_purge_heap);
        dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 5 * NSEC_PER_SEC, NSEC_PER_SEC);
        dispatch_source_set_event_handler(t, ^{ purge_report(); });
        dispatch_resume(t);
        static dispatch_source_t keep; keep = t; (void)keep;
        if (no_volatile()) vxmac_log("GRID Metal: GL_NO_VOLATILE=1: resources the game marks volatile are kept non-volatile");
    }
}
