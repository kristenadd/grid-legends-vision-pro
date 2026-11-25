// grid_stereo.m: the floating window in stereoscopic 3D. The game renders once, as on the Mac; each eye's picture is
// made from that frame and the scene's depth, so the race sits behind the window like a view through it: the player's
// car on the window's plane, the distance behind it, the nearest things a little in front. Shown by a RealityKit plane
// over the window whose material gives each eye its own texture (GridStereoView.swift, GridStereo.usda).
//
// - the depth: the host's pass hook (host.m, tools/sync_host.py hook 8: the window only; VXpro's own is for its
//   immersive presenter) names each render pass's depth attachment as the pass ends; the biggest at the frame's aspect
//   is the scene's (1920x1080 Depth32Float_Stencil8 in a race). It is copied at the present, in the present's command
//   buffer, when the GPU has that frame's depth in it: the game encodes on several threads, and the next frame's passes
//   (one of them clears this depth) are encoded before this frame's present - copied at its passes' ends, the depth was
//   the next frame's or none (ghosts on moving cars, half the frames flat). A depth not seen for 0.5 s (menus, videos):
//   none, and both eyes get the same picture. Its convention (1 or 0 for the sky) and the convergence (the depth at
//   the lower middle of the frame, the player's car in the chase view, smoothed over about a second) are read from it
//   on the CPU. Distances stay in the depth's own units (1/d or 1/(1-d)): the game's near plane cancels in the ratios.
// - the frame: at each present (host.m's present hook, hook 6) the drawable is copied into a slot with the depth, and
//   the game's scene picture before its UI (its 1920x1080 RGBA8 target, by identity from libglmtl's gl_frame_target).
// - the eyes: at each RealityKit update the newest slot is drawn into the two eye textures (grid_stereo_encode): each
//   eye's pixel is the frame's at c, where c + e (1 - conv / L(c)) is the pixel (e the eye's offset, half the eyes'
//   spacing, as a fraction of the window's physical width), found by a few fixed-point steps.
// - a capture on request (tools/vxmac_grid.py burst --eyes puts Documents/grid_eyes): the next stereo frame's two
//   eyes, the frame, the scene picture and the depth (grey: near light), raw in Documents/eyes as burst's
//   (index.txt), and every render pass of the next 3 frames in the log (libglmtl's gl_passlog_start).
//
//   GRID_STEREO=0          flat (the plane shows the frame to both eyes); default 1, a number scales the depth
//   GRID_STEREO_POP=0.3    how far the nearest point may come in front of the window (a fraction of the infinite
//                          point's parallax, the other way)
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <sys/stat.h>

void vxmac_log(const char *fmt, ...);

void vxmac_log_line(const char *line) { vxmac_log("%s", line); }   // (for GridStereoView.swift)
int grid_stereo_enabled(void) { const char *e = getenv("GRID_STEREO"); return !(e && atof(e) <= 0); }

static float envf(const char *n, float def) { const char *e = getenv(n); return e && *e ? (float)atof(e) : def; }
static float g_strength = -1, g_pop;
static void settings(void) {
    if (g_strength >= 0) return;
    g_strength = envf("GRID_STEREO", 1); g_pop = envf("GRID_STEREO_POP", 0.3f);
    vxmac_log("GRID stereo: %s (strength %.2f, pop-out at most %.0f %%)", g_strength > 0 ? "on" : "off (flat)", g_strength, g_pop * 100);
}

// ---- the slots: a frame, its depth and its scene picture --------------------------------------------------------------
enum { kSlots = 3 };
typedef struct {
    id<MTLTexture> color, color_view;   // (the drawable's copy; an sRGB view of it)
    id<MTLTexture> scene;               // (the game's scene picture before the UI, when found)
    id<MTLBuffer> depth;                // (R32 floats, shared: the CPU reads the probe points)
    uint32_t w, h, dw, dh;
    int has_depth, has_scene;
    uint64_t serial;
    int state;                          // 0 free, 1 being written, 2 ready
    int readers;                        // (the eyes' draw: not written while > 0)
} slot_t;
static slot_t g_slot[kSlots];
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static uint64_t g_serial;
static uint32_t g_frame_w, g_frame_h;   // (the last present's size: the depth must match its aspect)
static id<MTLTexture> g_scene_depth;    // (the scene's depth texture, by identity)
static double g_scene_depth_t;          // (when a pass last wrote it)
static int g_reversed = -1;
static float g_conv;
static double g_conv_t;
static float g_window_m = 1.2f;          // (the window's physical width, from GridStereoView.swift)

static int pick_write_slot(void) {   // (with g_lock: a free slot, else the oldest ready one nobody reads)
    int best = -1;
    for (int i = 0; i < kSlots; i++) if (g_slot[i].state == 0 && !g_slot[i].readers) return i;
    for (int i = 0; i < kSlots; i++) if (g_slot[i].state == 2 && !g_slot[i].readers && (best < 0 || g_slot[i].serial < g_slot[best].serial)) best = i;
    return best;
}

// ---- the depth: named by the game's render passes (host.m's pass hook in the window) ----------------------------
void grid_stereo_depth_pass(void *cbp, void *texp, int stores) {
    (void)cbp;
    settings();
    if (g_strength <= 0 || !stores) return;
    id<MTLTexture> t = (__bridge id<MTLTexture>)texp;
    if (t.parentTexture && t.parentTexture.pixelFormat == t.pixelFormat && t.parentTexture.width == t.width) t = t.parentTexture;   // (the game passes a new view each time)
    if (!t || (t.pixelFormat != MTLPixelFormatDepth32Float && t.pixelFormat != MTLPixelFormatDepth32Float_Stencil8)) return;
    if (t.textureType != MTLTextureType2D || t.sampleCount != 1) return;
    if (!g_frame_w || t.width * 2 < g_frame_w) return;   // (the scene's: at least half the frame's width, its aspect)
    double a = (double)t.width / t.height, fa = (double)g_frame_w / g_frame_h;
    if (fabs(a / fa - 1) > 0.02) return;
    pthread_mutex_lock(&g_lock);
    if (g_scene_depth != t && (!g_scene_depth || t.width * t.height >= g_scene_depth.width * g_scene_depth.height ||
                               CACurrentMediaTime() - g_scene_depth_t > 0.5)) {
        g_scene_depth = t;
        vxmac_log("GRID stereo: the scene's depth %lux%lu format %lu", (unsigned long)t.width, (unsigned long)t.height, (unsigned long)t.pixelFormat);
    }
    if (g_scene_depth == t) g_scene_depth_t = CACurrentMediaTime();
    pthread_mutex_unlock(&g_lock);
}

static float lin(float d, int rev) { return rev ? 1 / fmaxf(d, 1e-7f) : 1 / fmaxf(1 - d, 1e-7f); }
static void probe(const float *v, uint32_t w, uint32_t h) {   // (on a completed frame's depth)
    int ones = 0, zeros = 0;
    for (int i = 0; i < 8; i++) { float d = v[(size_t)(h * 0.03) * w + (size_t)(w * (0.15 + 0.1 * i))]; ones += d >= 0.9999f; zeros += d <= 0.0001f; }
    if (g_reversed < 0 && (ones >= 3 || zeros >= 3)) {
        g_reversed = zeros > ones;
        vxmac_log("GRID stereo: the game's depth is %s (the sky: %d of 8 at 1, %d at 0)", g_reversed ? "reversed" : "standard", ones, zeros);
    }
    if (g_reversed < 0) return;
    float m[9]; int n = 0;
    for (int i = 0; i < 9; i++) {
        float d = v[(size_t)(h * (0.62 + 0.07 * (i / 3))) * w + (size_t)(w * (0.42 + 0.08 * (i % 3)))];
        if (d > 0.0001f && d < 0.9999f) m[n++] = lin(d, g_reversed);
    }
    if (n < 3) return;
    for (int i = 1; i < n; i++) for (int j = i; j > 0 && m[j] < m[j - 1]; j--) { float x = m[j]; m[j] = m[j - 1]; m[j - 1] = x; }
    double now = CACurrentMediaTime();
    if (g_conv <= 0) { g_conv = m[n / 2]; vxmac_log("GRID stereo: convergence %.4g (depth units) from the frame's lower middle", g_conv); }
    else { float a = (float)fmin(1.0, (now - g_conv_t) / 1.0); g_conv = expf(logf(g_conv) * (1 - a) + logf(m[n / 2]) * a); }
    g_conv_t = now;
}

// ---- the capture (burst --eyes) ------------------------------------------------------------------------------------
static dispatch_queue_t g_cap_q;
static volatile int g_cap;   // (1 asked; 2 the next 3 presents' drawables and depths (frame0-2, depth0-2); 3 then the eyes)
static NSString *docs(void) { return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject; }
static void check_capture_request(void) {
    static double next;
    double now = CACurrentMediaTime();
    if (now < next) return;
    next = now + 0.5;
    NSString *req = [docs() stringByAppendingPathComponent:@"grid_eyes"];
    struct stat st;
    if (stat(req.fileSystemRepresentation, &st) != 0) return;
    unlink(req.fileSystemRepresentation);
    if (!g_cap_q) g_cap_q = dispatch_queue_create("grid.stereo.capture", DISPATCH_QUEUE_SERIAL);
    g_cap = 1;
    void (*passlog)(int) = (void (*)(int))dlsym(RTLD_DEFAULT, "gl_passlog_start");
    if (passlog) passlog(3);
    vxmac_log("GRID stereo: capture asked for");
}
static void write_raw(NSString *dir, NSString *name, NSData *bgra, uint32_t w, uint32_t h) {
    [bgra writeToFile:[dir stringByAppendingPathComponent:[name stringByAppendingString:@".bgra"]] atomically:NO];
    NSString *idx = [dir stringByAppendingPathComponent:@"index.txt"];
    NSString *line = [NSString stringWithFormat:@"%@ %u %u %u 0\n", name, w, h, w * 4];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:idx];
    if (!fh) { [NSFileManager.defaultManager createFileAtPath:idx contents:nil attributes:nil]; fh = [NSFileHandle fileHandleForWritingAtPath:idx]; }
    [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile];
}
static id<MTLBuffer> readback(id<MTLBlitCommandEncoder> b, id<MTLDevice> dev, id<MTLTexture> t) {
    if (!t) return nil;
    id<MTLBuffer> buf = [dev newBufferWithLength:t.width * t.height * 4 options:MTLResourceStorageModeShared];
    [b copyFromTexture:t sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(t.width, t.height, 1)
              toBuffer:buf destinationOffset:0 destinationBytesPerRow:t.width * 4 destinationBytesPerImage:t.width * t.height * 4];
    return buf;
}
static NSData *bgra_from(const uint8_t *p, NSUInteger w, NSUInteger h, int rgba, int flip) {
    NSMutableData *o = [NSMutableData dataWithLength:w * h * 4]; uint8_t *q = o.mutableBytes;
    for (NSUInteger y = 0; y < h; y++) for (NSUInteger x = 0; x < w; x++) {
        const uint8_t *a = p + ((flip ? h - 1 - y : y) * w + x) * 4; uint8_t *z = q + (y * w + x) * 4;
        z[0] = rgba ? a[2] : a[0]; z[1] = a[1]; z[2] = rgba ? a[0] : a[2]; z[3] = 255;
    }
    return o;
}
static NSData *depth_grey(const float *v, uint32_t dw, uint32_t dh, float conv, int rev) {   // (white near, mid grey on the window, black far)
    NSMutableData *o = [NSMutableData dataWithLength:(NSUInteger)dw * dh * 4]; uint8_t *q = o.mutableBytes;
    for (size_t i = 0; i < (size_t)dw * dh; i++) {
        float L = lin(v[i], rev), f = 1 - conv / L; if (f > 1) f = 1; if (f < -1) f = -1;
        uint8_t g = (uint8_t)(127.5f - f * 127.5f); q[i * 4] = q[i * 4 + 1] = q[i * 4 + 2] = g; q[i * 4 + 3] = 255;
    }
    return o;
}
static void capture_eyes(id<MTLCommandBuffer> cb, id<MTLTexture> l, id<MTLTexture> r, slot_t *S, int on) {
    id<MTLBlitCommandEncoder> b = [cb blitCommandEncoder];
    id<MTLBuffer> bl = readback(b, cb.device, l), br = readback(b, cb.device, r), bf = readback(b, cb.device, S->color);
    id<MTLBuffer> bs = S->has_scene ? readback(b, cb.device, S->scene) : nil;
    [b endEncoding];
    NSUInteger w = l.width, h = l.height, fw = S->color.width, fh = S->color.height, sw = S->scene.width, sh = S->scene.height;
    MTLPixelFormat sf = S->scene.pixelFormat;
    float conv = g_conv; int rev = g_reversed;
    id<MTLBuffer> dbuf = on && S->has_depth ? S->depth : nil; uint32_t dw = S->dw, dh = S->dh;
    [cb addCompletedHandler:^(id<MTLCommandBuffer> c) {
        (void)c;
        dispatch_async(g_cap_q, ^{
            NSString *dir = [docs() stringByAppendingPathComponent:@"eyes"];
            [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
            // (the eyes: RGBA, stored bottom row first for RealityKit)
            write_raw(dir, @"left", bgra_from(bl.contents, w, h, 1, 1), (uint32_t)w, (uint32_t)h);
            write_raw(dir, @"right", bgra_from(br.contents, w, h, 1, 1), (uint32_t)w, (uint32_t)h);
            write_raw(dir, @"frame", [NSData dataWithBytes:bf.contents length:fw * fh * 4], (uint32_t)fw, (uint32_t)fh);
            if (bs) write_raw(dir, @"scene", bgra_from(bs.contents, sw, sh, sf != MTLPixelFormatBGRA8Unorm, 0), (uint32_t)sw, (uint32_t)sh);
            if (dbuf) write_raw(dir, @"depth", depth_grey(dbuf.contents, dw, dh, conv, rev), dw, dh);
            vxmac_log("GRID stereo: captured the eyes, the frame%s%s in %s", bs ? ", the scene picture" : "", dbuf ? " and the depth" : "", dir.UTF8String);
        });
    }];
}

// ---- the frame: host.m's present hook, in the window ----------------------------------------------------------------
void grid_stereo_frame(void *cbp, void *texp, uint32_t w, uint32_t h) {
    settings();
    id<MTLCommandBuffer> cb = (__bridge id<MTLCommandBuffer>)cbp;
    id<MTLTexture> t = (__bridge id<MTLTexture>)texp;
    g_frame_w = w; g_frame_h = h;
    { static void (*frame_end)(void); static int once; if (!once++) frame_end = (void (*)(void))dlsym(RTLD_DEFAULT, "gl_passlog_frame"); if (frame_end) frame_end(); }
    check_capture_request();
    if (t.pixelFormat != MTLPixelFormatBGRA8Unorm && t.pixelFormat != MTLPixelFormatBGRA8Unorm_sRGB) return;
    double now = CACurrentMediaTime();
    pthread_mutex_lock(&g_lock);
    int s = pick_write_slot();
    if (s >= 0) g_slot[s].state = 1;
    id<MTLTexture> dt = g_strength > 0 && now - g_scene_depth_t < 0.5 ? g_scene_depth : nil;
    pthread_mutex_unlock(&g_lock);
    if (s < 0) return;
    slot_t *S = &g_slot[s];
    if (!S->color || S->color.width != t.width || S->color.height != t.height) {
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:t.width height:t.height mipmapped:NO];
        td.usage = MTLTextureUsageShaderRead | MTLTextureUsagePixelFormatView; td.storageMode = MTLStorageModePrivate;
        S->color = [cb.device newTextureWithDescriptor:td];
        S->color_view = [S->color newTextureViewWithPixelFormat:MTLPixelFormatBGRA8Unorm_sRGB];
    }
    id<MTLBlitCommandEncoder> b = [cb blitCommandEncoder];
    [b copyFromTexture:t sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(t.width, t.height, 1)
             toTexture:S->color destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0, 0, 0)];
    S->has_depth = 0;
    if (dt) {   // (the scene's depth as the GPU has it now: this frame's)
        NSUInteger need = dt.width * dt.height * 4;
        if (!S->depth || S->depth.length < need) S->depth = [cb.device newBufferWithLength:need options:MTLResourceStorageModeShared];
        [b copyFromTexture:dt sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(dt.width, dt.height, 1)
                  toBuffer:S->depth destinationOffset:0 destinationBytesPerRow:dt.width * 4 destinationBytesPerImage:need
                   options:dt.pixelFormat == MTLPixelFormatDepth32Float_Stencil8 ? MTLBlitOptionDepthFromDepthStencil : MTLBlitOptionNone];
        S->dw = (uint32_t)dt.width; S->dh = (uint32_t)dt.height; S->has_depth = 1;
    }
    // (the game's scene picture before its UI: its frame-sized RGBA8 target)
    S->has_scene = 0;
    static void *(*target)(uint32_t, uint32_t, uint32_t); static int once;
    if (!once++) target = (void *(*)(uint32_t, uint32_t, uint32_t))dlsym(RTLD_DEFAULT, "gl_frame_target");
    id<MTLTexture> sc = target && dt ? (__bridge id<MTLTexture>)target(w, h, MTLPixelFormatRGBA8Unorm) : nil;
    if (sc) {
        if (!S->scene || S->scene.width != sc.width || S->scene.height != sc.height || S->scene.pixelFormat != sc.pixelFormat) {
            MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:sc.pixelFormat width:sc.width height:sc.height mipmapped:NO];
            td.usage = MTLTextureUsageShaderRead | MTLTextureUsagePixelFormatView; td.storageMode = MTLStorageModePrivate;
            S->scene = [cb.device newTextureWithDescriptor:td];
        }
        [b copyFromTexture:sc sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(sc.width, sc.height, 1)
                 toTexture:S->scene destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0, 0, 0)];
        S->has_scene = 1;
    }
    // (the capture's run of consecutive presents: each one's drawable and the depth copied with it, raw)
    static int run = 0;
    if (g_cap == 1 && S->has_depth) { g_cap = 2; run = 0; }
    if (g_cap == 2) {
        id<MTLBuffer> fb = readback(b, cb.device, S->color);
        id<MTLBuffer> db = [cb.device newBufferWithLength:S->dw * S->dh * 4 options:MTLResourceStorageModeShared];
        [b copyFromBuffer:S->depth sourceOffset:0 toBuffer:db destinationOffset:0 size:S->dw * S->dh * 4];
        int k = run++; uint32_t fw = (uint32_t)S->color.width, fh = (uint32_t)S->color.height, dw = S->dw, dh = S->dh;
        float conv = g_conv; int rev = g_reversed;
        if (run >= 3) g_cap = 3;   // (then the eyes, at the next stereo draw)
        [cb addCompletedHandler:^(id<MTLCommandBuffer> c) {
            (void)c;
            dispatch_async(g_cap_q, ^{
                NSString *dir = [docs() stringByAppendingPathComponent:@"eyes"];
                if (k == 0) { [NSFileManager.defaultManager removeItemAtPath:dir error:nil];
                              [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil]; }
                write_raw(dir, [NSString stringWithFormat:@"frame%d", k], [NSData dataWithBytes:fb.contents length:(NSUInteger)fw * fh * 4], fw, fh);
                write_raw(dir, [NSString stringWithFormat:@"depth%d", k], depth_grey(db.contents, dw, dh, conv, rev), dw, dh);
            });
        }];
    }
    [b endEncoding];
    S->w = (uint32_t)t.width; S->h = (uint32_t)t.height;
    uint64_t serial = ++g_serial;
    int probe_it = S->has_depth;
    [cb addCompletedHandler:^(id<MTLCommandBuffer> c) {
        if (c.status == MTLCommandBufferStatusCompleted && probe_it) probe(S->depth.contents, S->dw, S->dh);
        pthread_mutex_lock(&g_lock);
        S->serial = serial; S->state = c.status == MTLCommandBufferStatusCompleted ? 2 : 0;
        pthread_mutex_unlock(&g_lock);
    }];
}

// ---- the eyes (GridStereoView.swift, at each RealityKit update) -------------------------------------------------------
int grid_stereo_take(int32_t *w, int32_t *h) {   // (the newest ready slot, held until grid_stereo_release)
    pthread_mutex_lock(&g_lock);
    int best = -1;
    for (int i = 0; i < kSlots; i++) if (g_slot[i].state == 2 && (best < 0 || g_slot[i].serial > g_slot[best].serial)) best = i;
    static uint64_t last;
    if (best >= 0 && g_slot[best].serial == last) best = -1;   // (nothing new)
    if (best >= 0) { g_slot[best].readers++; last = g_slot[best].serial; *w = (int32_t)g_slot[best].w; *h = (int32_t)g_slot[best].h; }
    pthread_mutex_unlock(&g_lock);
    return best;
}
void grid_stereo_release(int s) {
    if (s < 0 || s >= kSlots) return;
    pthread_mutex_lock(&g_lock); if (g_slot[s].readers > 0) g_slot[s].readers--; pthread_mutex_unlock(&g_lock);
}
void grid_stereo_set_window_width(float m) { if (m > 0.05f) g_window_m = m; }

static NSString *const kEyeSrc = @
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct P { float shift; float conv; float rev; float pop; uint dw; uint dh; float on; float pad; };\n"
    "struct V { float4 p [[position]]; float2 uv; };\n"
    // (stored bottom row first: RealityKit's plane reads it that way)
    "vertex V ev(uint i [[vertex_id]]) { float2 q = float2((i << 1) & 2, i & 2); V o; o.p = float4(q * 2 - 1, 0, 1); o.uv = float2(q.x, q.y); return o; }\n"
    "fragment float4 ef(V in [[stage_in]], constant P &p [[buffer(0)]], texture2d<float> img [[texture(0)]], const device float *dep [[buffer(1)]]) {\n"
    "    constexpr sampler s(filter::linear, address::clamp_to_edge);\n"
    "    float2 c = in.uv;\n"
    "    if (p.on > 0) {\n"
    "        for (int k = 0; k < 4; k++) {\n"
    "            uint2 q = uint2(clamp(c, 0.0, 0.9999) * float2(p.dw, p.dh));\n"
    "            float d = dep[q.y * p.dw + q.x];\n"
    "            float L = p.rev > 0 ? 1 / max(d, 1e-7) : 1 / max(1 - d, 1e-7);\n"
    "            float f = clamp(1 - p.conv / L, -p.pop, 1.0);\n"
    "            c = float2(in.uv.x + p.shift * f, in.uv.y);\n"
    "        }\n"
    "    }\n"
    "    return float4(img.sample(s, clamp(c, 0.0, 1.0)).rgb, 1);\n"
    "}\n";
static id<MTLRenderPipelineState> g_pso; static MTLPixelFormat g_pso_fmt;

// (draws slot s into the two eye textures (RealityKit's LowLevelTextures) in cb)
void grid_stereo_encode(int s, void *cbp, void *leftp, void *rightp) {
    if (s < 0 || s >= kSlots) return;
    id<MTLCommandBuffer> cb = (__bridge id<MTLCommandBuffer>)cbp;
    id<MTLTexture> eyes[2] = { (__bridge id<MTLTexture>)leftp, (__bridge id<MTLTexture>)rightp };
    slot_t *S = &g_slot[s];
    if (!S->color || !eyes[0] || !eyes[1]) return;
    if (!g_pso || g_pso_fmt != eyes[0].pixelFormat) {
        NSError *err = nil;
        id<MTLLibrary> lib = [cb.device newLibraryWithSource:kEyeSrc options:nil error:&err];
        if (!lib) { vxmac_log("GRID stereo: shader: %s", err.localizedDescription.UTF8String); return; }
        MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
        pd.vertexFunction = [lib newFunctionWithName:@"ev"]; pd.fragmentFunction = [lib newFunctionWithName:@"ef"];
        pd.colorAttachments[0].pixelFormat = eyes[0].pixelFormat;
        g_pso = [cb.device newRenderPipelineStateWithDescriptor:pd error:&err];
        if (!g_pso) { vxmac_log("GRID stereo: pipeline: %s", err.localizedDescription.UTF8String); return; }
        g_pso_fmt = eyes[0].pixelFormat;
    }
    int on = g_strength > 0 && S->has_depth && g_reversed >= 0 && g_conv > 0;
    static int told_on = -1;
    if (on != told_on) { told_on = on; vxmac_log("GRID stereo: %s", on ? "3D (the frame has depth)" : "flat (no depth: menus, videos, or not read yet)"); }
    // (half the eyes' spacing (63 mm) as a fraction of the window's width: the parallax of a point at infinity)
    float half = 0.0315f * g_strength / g_window_m;
    for (int e = 0; e < 2; e++) {
        struct { float shift, conv, rev, pop; uint32_t dw, dh; float on, pad; } P = {
            e == 0 ? half : -half, g_conv, (float)g_reversed, g_pop, on ? S->dw : 1, on ? S->dh : 1, (float)on, 0 };
        MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor new];
        pass.colorAttachments[0].texture = eyes[e]; pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
        pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:pass];
        [enc setRenderPipelineState:g_pso];
        [enc setFragmentBytes:&P length:sizeof P atIndex:0];
        [enc setFragmentTexture:S->color_view atIndex:0];
        static float zero;
        if (on) [enc setFragmentBuffer:S->depth offset:0 atIndex:1]; else [enc setFragmentBytes:&zero length:4 atIndex:1];
        [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [enc endEncoding];
    }
    if (g_cap == 3) { g_cap = 0; capture_eyes(cb, eyes[0], eyes[1], S, on); }
}
