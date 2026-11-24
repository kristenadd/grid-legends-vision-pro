// glcommon.m: in libglkit (every other gl* library links libglkit for these).
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <pthread.h>
#include <string.h>
#include "glcommon.h"

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableSet *g_seen;

void gl_log_once(const char *what) {
    pthread_mutex_lock(&g_lock);
    if (!g_seen) g_seen = [NSMutableSet new];
    NSString *k = @(what);
    BOOL fresh = ![g_seen containsObject:k];
    if (fresh) [g_seen addObject:k];
    pthread_mutex_unlock(&g_lock);
    if (fresh) vxmac_log("GRID shim: %s", what);
}

static pthread_t g_program_thread;
static CFRunLoopRef g_program_runloop;
void gl_set_program_thread(void) {
    g_program_thread = pthread_self();
    g_program_runloop = (CFRunLoopRef)CFRetain(CFRunLoopGetCurrent());
}
int gl_on_program_thread(void) { return g_program_thread && pthread_equal(pthread_self(), g_program_thread); }
void *gl_program_runloop(void) { return g_program_runloop; }

static id gl_zero_imp(id self, SEL _cmd, ...) { (void)self; (void)_cmd; return nil; }

BOOL gl_resolve(Class cls, SEL sel, BOOL meta) {
    const char *name = sel_getName(sel);
    // (selectors the runtime itself probes for must stay unresolved)
    if (!strncmp(name, "_", 1) || !strcmp(name, "forwardingTargetForSelector:") || !strcmp(name, "methodSignatureForSelector:") ||
        !strncmp(name, ".cxx", 4) || !strcmp(name, "initialize") || !strcmp(name, "load") || !strncmp(name, "accessibility", 13))
        return NO;
    char item[256];
    snprintf(item, sizeof item, "not implemented: %s %c%s (returns 0)", class_getName(cls), meta ? '+' : '-', name);
    gl_log_once(item);
    class_addMethod(meta ? object_getClass(cls) : cls, sel, (IMP)gl_zero_imp, "@@:");
    return YES;
}
