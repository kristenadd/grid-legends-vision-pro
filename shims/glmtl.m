// libglmtl: Metal for GRID Legends. Re-exports libvxmtl (VXpro's Metal: present hook, pacing, macOS-only methods made
// no-ops) and adds:
// - the three macOS device notification names;
// - MTLStorageModeManaged (macOS only; visionOS's Metal refuses it) as Shared: on Apple silicon's unified memory a
//   managed resource is one shared copy anyway, and its didModifyRange: / synchronizeResource: are no-ops (libvxmtl).
//   Depth and stencil textures, which cannot be shared, become Private.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
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
    }
}
