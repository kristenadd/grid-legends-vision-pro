// libglca: CoreAudio for GRID Legends. Re-exports CoreAudio. VXpro (vxaudio.m, h67) answers the game's HAL questions
// without the HAL by default (AudioObjectGetPropertyData / GetPropertyDataSize / SetPropertyData: one output device,
// 0x7678); GRID also calls AudioObjectHasProperty and the property listeners, which still started the real HAL in the
// app: its Bluetooth plug-in trapped (SIGTRAP in xpc) on the headset. These three are answered here without the HAL too:
// - HasProperty: yes for the system object (1) and VXpro's device (0x7678), no otherwise; the value itself then comes
//   from VXpro's answers (an unknown property gets its error there, as on a Mac);
// - Add/RemovePropertyListener: accepted; nothing changes, so they never fire.
// VXMAC_AUDIO_HAL=1 (VXpro's switch back to the real HAL) passes all three through.
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "glcommon.h"

typedef int32_t OSStatus_;
typedef struct { uint32_t sel, scope, elem; } HALAddr;
typedef OSStatus_ (*listener_fn)(uint32_t, uint32_t, const HALAddr *, void *);
enum { kSystemObject = 1, kVXDevice = 0x7678 };

static int real_hal(void) { const char *h = getenv("VXMAC_AUDIO_HAL"); return h && !strcmp(h, "1"); }
static void *real(const char *name) {
    static void *ca;
    if (!ca) ca = dlopen("/System/Library/Frameworks/CoreAudio.framework/CoreAudio", RTLD_NOLOAD | RTLD_LAZY);
    return dlsym(ca, name);
}

uint8_t AudioObjectHasProperty(uint32_t obj, const HALAddr *a) {
    if (real_hal()) return ((uint8_t (*)(uint32_t, const HALAddr *))real("AudioObjectHasProperty"))(obj, a);
    gl_log_once("CoreAudio: AudioObjectHasProperty answered without the HAL");
    return obj == kSystemObject || obj == kVXDevice;
}
OSStatus_ AudioObjectAddPropertyListener(uint32_t obj, const HALAddr *a, listener_fn fn, void *ctx) {
    if (real_hal()) return ((OSStatus_ (*)(uint32_t, const HALAddr *, listener_fn, void *))real("AudioObjectAddPropertyListener"))(obj, a, fn, ctx);
    gl_log_once("CoreAudio: AudioObjectAddPropertyListener accepted without the HAL (never fires)");
    return 0;
}
OSStatus_ AudioObjectRemovePropertyListener(uint32_t obj, const HALAddr *a, listener_fn fn, void *ctx) {
    if (real_hal()) return ((OSStatus_ (*)(uint32_t, const HALAddr *, listener_fn, void *))real("AudioObjectRemovePropertyListener"))(obj, a, fn, ctx);
    return 0;
}
