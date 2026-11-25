// grid_burst.m: a burst of the game's frames, on request, for looking at flicker from the Mac (visionOS has no screen
// recording or screenshots for devicectl). Called for every presented frame from host.m's present hook
// (tools/sync_host.py).
//
// tools/vxmac_grid.py burst puts Documents/grid_burst on the headset; within half a second every second frame
// for 4 s (or as the file says: "step frames") is read back at full size and written raw, as the frame is, to
// Documents/burst/NNN.bgra (32-bit BGRA), with Documents/burst/index.txt: "frame width height bytesPerRow seconds" per
// line. The tool copies them back and converts them to PNG.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <sys/stat.h>

void vxmac_log(const char *fmt, ...);

static double g_next_check, g_start;
static int g_left, g_n, g_step = 2, g_count;
static NSString *g_dir;
static dispatch_queue_t g_q;

void grid_burst(void *cbp, void *texp, double tn) {
#ifdef GRID_QUIET
    (void)cbp; (void)texp; (void)tn; return;   // (tools/vxmac_grid.py build --quiet: no bursts)
#endif
    if (!g_left) {
        if (tn < g_next_check) return;
        g_next_check = tn + 0.5;
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *req = [docs stringByAppendingPathComponent:@"grid_burst"];
        struct stat st;
        if (stat(req.fileSystemRepresentation, &st) != 0) return;
        NSString *spec = [NSString stringWithContentsOfFile:req encoding:NSUTF8StringEncoding error:nil];
        unlink(req.fileSystemRepresentation);
        g_dir = [docs stringByAppendingPathComponent:@"burst"];
        [NSFileManager.defaultManager removeItemAtPath:g_dir error:nil];
        [NSFileManager.defaultManager createDirectoryAtPath:g_dir withIntermediateDirectories:YES attributes:nil error:nil];
        int step = 0, frames = 0;   // (the request's text: "step frames"; empty: every second frame, 120)
        if (spec) sscanf(spec.UTF8String, "%d %d", &step, &frames);
        g_step = step > 0 ? step : 2; g_left = frames > 0 && frames <= 300 ? frames : 120;
        if (!g_q) g_q = dispatch_queue_create("grid.burst", DISPATCH_QUEUE_SERIAL);
        g_n = 0; g_count = 0; g_start = tn;
        vxmac_log("GRID: frame burst: %d frames, every %d", g_left, g_step);
    }
    if (g_count++ % g_step) return;
    id<MTLCommandBuffer> cb = (__bridge id<MTLCommandBuffer>)cbp;
    id<MTLTexture> t = (__bridge id<MTLTexture>)texp;
    int k = g_n++;
    if (--g_left == 0) vxmac_log("GRID: frame burst done: %d frames in %s", g_n, g_dir.UTF8String);
    if (t.pixelFormat != MTLPixelFormatBGRA8Unorm && t.pixelFormat != MTLPixelFormatBGRA8Unorm_sRGB) return;
    NSUInteger w = t.width, h = t.height, row = w * 4;
    id<MTLBuffer> b = [cb.device newBufferWithLength:row * h options:MTLResourceStorageModeShared];
    id<MTLBlitCommandEncoder> enc = [cb blitCommandEncoder];
    [enc copyFromTexture:t sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(w, h, 1)
                toBuffer:b destinationOffset:0 destinationBytesPerRow:row destinationBytesPerImage:row * h];
    [enc endEncoding];
    NSString *dir = g_dir; double at = tn - g_start;
    [cb addCompletedHandler:^(id<MTLCommandBuffer> c) {
        (void)c;
        dispatch_async(g_q, ^{
            [[NSData dataWithBytesNoCopy:b.contents length:row * h freeWhenDone:NO]
                writeToFile:[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%03d.bgra", k]] atomically:NO];
            NSString *line = [NSString stringWithFormat:@"%03d %lu %lu %lu %.4f\n", k, (unsigned long)w, (unsigned long)h, (unsigned long)row, at];
            NSString *idx = [dir stringByAppendingPathComponent:@"index.txt"];
            NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:idx];
            if (!fh) { [NSFileManager.defaultManager createFileAtPath:idx contents:nil attributes:nil]; fh = [NSFileHandle fileHandleForWritingAtPath:idx]; }
            [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile];
            (void)b;   // (kept alive until written)
        });
    }];
}
