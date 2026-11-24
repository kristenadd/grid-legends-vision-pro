// libglsystem: libSystem for GRID Legends. Re-exports libvxsystem (VXpro: libSystem + _NSGetExecutablePath, syslog)
// and adds:
// - pthread_main_np: 1 on the game thread, the game's main thread (see glcommon.h);
// - the ways out of the process (_exit, _Exit, execv, abort, raise, pthread_kill with a fatal signal): logged with the
//   calling stack (frames in the game as GRIDLegends.dylib+offset), then done as asked.
#include <dlfcn.h>
#include <execinfo.h>
#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "glcommon.h"

int pthread_main_np(void) {
    if (gl_on_program_thread()) { gl_log_once("libSystem: pthread_main_np -> 1 on the game thread"); return 1; }
    return 0;   // (other game threads; UIKit's main thread is never the game's)
}

static void *real(const char *name) {
    static void *libc;
    if (!libc) libc = dlopen("/usr/lib/libSystem.B.dylib", RTLD_NOLOAD | RTLD_LAZY);
    return dlsym(libc, name);
}

static void stack(const char *what) {
    vxmac_log("GRID: %s", what);
    void *f[40]; int n = backtrace(f, 40);
    for (int i = 1; i < n; i++) {
        Dl_info d;
        if (dladdr(f[i], &d) && d.dli_fname) {
            const char *b = strrchr(d.dli_fname, '/');
            vxmac_log("GRID:   %2d %s+%#lx %s", i, b ? b + 1 : d.dli_fname, (unsigned long)((char *)f[i] - (char *)d.dli_fbase), d.dli_sname ? d.dli_sname : "");
        }
    }
}

void _exit(int status) {
    char m[64]; snprintf(m, sizeof m, "_exit(%d)", status); stack(m);
    ((void (*)(int))real("_exit"))(status);
    __builtin_unreachable();
}
void _Exit(int status) {
    char m[64]; snprintf(m, sizeof m, "_Exit(%d)", status); stack(m);
    ((void (*)(int))real("_Exit"))(status);
    __builtin_unreachable();
}
int execv(const char *path, char *const argv[]) {
    char m[1100]; snprintf(m, sizeof m, "execv(%s)", path ? path : "(null)"); stack(m);
    return ((int (*)(const char *, char *const[]))real("execv"))(path, argv);
}
void abort(void) {
    stack("abort()");
    ((void (*)(void))real("abort"))();
    __builtin_unreachable();
}
int raise(int sig) {
    char m[64]; snprintf(m, sizeof m, "raise(%d)", sig); stack(m);
    return ((int (*)(int))real("raise"))(sig);
}
int pthread_kill(pthread_t t, int sig) {
    if (sig != 0 && sig != SIGURG) { char m[64]; snprintf(m, sizeof m, "pthread_kill(sig %d)", sig); stack(m); }
    return ((int (*)(pthread_t, int))real("pthread_kill"))(t, sig);
}
