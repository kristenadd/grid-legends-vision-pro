// GRID Legends shims: helpers shared by the gl* libraries. Each library re-exports a VXpro shim (libvx*) or the
// visionOS framework of the same name and adds only what GRID Legends imports and visionOS lacks
// (docs/PHASE0.md, tools/grid_prepare.py's SHIMMED map).
#pragma once
#include <stdio.h>
#include <stdarg.h>

#ifdef __cplusplus
extern "C" {
#endif

// libvxkit's logger (Documents/vxmac_host.jsonl on the headset; stderr elsewhere).
void vxmac_log(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

// The game's main thread: the thread that called NSApplicationMain (the host's "program main" thread). On a Mac it
// is the process's main thread; here UIKit has that one, so main-thread questions from the game are answered for it
// (pthread_main_np in libglsystem, CFRunLoopGetMain in libglcf).
void gl_set_program_thread(void);
int gl_on_program_thread(void);
void *gl_program_runloop(void);   // (CFRunLoopRef; NULL before NSApplicationMain)

// Log a call once per call site name ("OpenAL: alcOpenDevice"), so stubs show up in the log without flooding it.
void gl_log_once(const char *what);

#ifdef __OBJC__
#import <objc/runtime.h>
// The catch-all for stand-in classes: an unknown selector is added as a method returning 0 and logged once.
BOOL gl_resolve(Class cls, SEL sel, BOOL meta);
#define GL_CATCHALL \
    + (BOOL)resolveInstanceMethod:(SEL)sel { return gl_resolve(self, sel, NO); } \
    + (BOOL)resolveClassMethod:(SEL)sel { return gl_resolve(self, sel, YES); }
#endif

#ifdef __cplusplus
}
#endif
