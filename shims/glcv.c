// libglcv: CoreVideo for GRID Legends. Re-exports visionOS's CoreVideo and adds CVDisplayLink (macOS only): a
// dispatch timer at the screen rate (GL_DISPLAY_HZ, default 90, as libvxkit's NSScreen) calling the output callback
// with Mac-shaped time stamps.
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <mach/mach_time.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "glcommon.h"

// (the macOS CVTimeStamp layout)
typedef struct { int16_t subframes, subframeDivisor; uint32_t counter, type, flags; int16_t hours, minutes, seconds, frames; } GLSMPTETime;
typedef struct {
    uint32_t version; int32_t videoTimeScale; int64_t videoTime; uint64_t hostTime; double rateScalar;
    int64_t videoRefreshPeriod; GLSMPTETime smpteTime; uint64_t flags, reserved;
} GLTimeStamp;
typedef int32_t (*GLOutputCallback)(void *link, const GLTimeStamp *now, const GLTimeStamp *out, uint64_t flagsIn, uint64_t *flagsOut, void *ctx);

typedef struct { dispatch_source_t timer; GLOutputCallback cb; void *ctx; int64_t frame; double hz; int running; } GLLink;

enum { kTSVideoTimeValid = 1 << 0, kTSHostTimeValid = 1 << 1, kTSVideoRefreshPeriodValid = 1 << 4 };

static double rate(void) { const char *e = getenv("GL_DISPLAY_HZ"); double h = e ? atof(e) : 0; return h > 1 ? h : 90.0; }
static uint64_t ns_to_host(uint64_t ns) { static mach_timebase_info_data_t tb; if (!tb.denom) mach_timebase_info(&tb); return ns * tb.denom / tb.numer; }

int32_t CVDisplayLinkCreateWithActiveCGDisplays(GLLink **out) {
    GLLink *l = calloc(1, sizeof *l);
    l->hz = rate();
    *out = l;
    gl_log_once("CoreVideo: CVDisplayLink stand-in (timer)");
    return 0;
}
int32_t CVDisplayLinkSetCurrentCGDisplay(GLLink *l, uint32_t d) { (void)l; (void)d; return 0; }
int32_t CVDisplayLinkSetOutputCallback(GLLink *l, GLOutputCallback cb, void *ctx) { l->cb = cb; l->ctx = ctx; return 0; }

static void tick(GLLink *l) {
    if (!l->cb) return;
    int64_t scale = 1000000;   // (video time in microseconds)
    int64_t period = (int64_t)(scale / l->hz);
    GLTimeStamp now = {0}, out = {0};
    now.videoTimeScale = out.videoTimeScale = (int32_t)scale;
    now.videoRefreshPeriod = out.videoRefreshPeriod = period;
    now.rateScalar = out.rateScalar = 1.0;
    now.flags = out.flags = kTSVideoTimeValid | kTSHostTimeValid | kTSVideoRefreshPeriodValid;
    now.videoTime = l->frame * period;
    now.hostTime = mach_absolute_time();
    out.videoTime = now.videoTime + period;
    out.hostTime = now.hostTime + ns_to_host((uint64_t)(1e9 / l->hz));
    l->frame++;
    uint64_t fo = 0;
    l->cb(l, &now, &out, 0, &fo, l->ctx);
}

int32_t CVDisplayLinkStart(GLLink *l) {
    if (l->running) return 0;
    if (!l->timer) {
        l->timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, DISPATCH_TIMER_STRICT,
                                          dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0));
        uint64_t ns = (uint64_t)(1e9 / l->hz);
        dispatch_source_set_timer(l->timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)ns), ns, ns / 20);
        dispatch_source_set_event_handler(l->timer, ^{ tick(l); });
    }
    dispatch_resume(l->timer);
    l->running = 1;
    return 0;
}
int32_t CVDisplayLinkStop(GLLink *l) {
    if (l->running) { dispatch_suspend(l->timer); l->running = 0; }
    return 0;
}
void CVDisplayLinkRelease(GLLink *l) {
    if (!l) return;
    if (l->timer) {
        // (the link is freed once cancellation has run, so no tick can still be using it)
        dispatch_source_set_cancel_handler(l->timer, ^{ free(l); });
        dispatch_source_cancel(l->timer);
        if (!l->running) dispatch_resume(l->timer);   // (a suspended source must be resumed for the cancel to run)
        return;
    }
    free(l);
}
