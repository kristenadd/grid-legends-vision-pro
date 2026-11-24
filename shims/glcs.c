// libglcs: CoreServices for GRID Legends. Re-exports visionOS's CoreServices and libSystem (the Mac's CoreServices
// re-exports libm: exp2, fesetround, modff, nanf and nextafterf are bound to it) and adds the Mac-only calls.
#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>
#include <string.h>
#include "glcommon.h"

typedef int16_t OSErr_;
typedef int32_t OSStatus_;

// Gestalt: the system version selectors as a macOS 14.0 Mac would answer; everything else unknown.
OSErr_ Gestalt(uint32_t selector, int32_t *response) {
    switch (selector) {
    case 'sysv': *response = 0x1099; return 0;   // (BCD 0x10XY cannot express 14: saturated; callers use sys1/sys2)
    case 'sys1': *response = 14; return 0;
    case 'sys2': *response = 0; return 0;
    case 'sys3': *response = 0; return 0;
    }
    char m[64]; snprintf(m, sizeof m, "CoreServices: Gestalt '%c%c%c%c' -> gestaltUndefSelectorErr",
                         (char)(selector >> 24), (char)(selector >> 16), (char)(selector >> 8), (char)selector);
    gl_log_once(m);
    return -5551;
}

// Launch Services: no other applications here.
CFArrayRef LSCopyApplicationURLsForBundleIdentifier(CFStringRef bid, CFErrorRef *err) {
    (void)bid;
    if (err) *err = NULL;
    return NULL;
}
OSStatus_ LSOpenCFURLRef(CFURLRef url, CFURLRef *launched) {
    (void)url;
    if (launched) *launched = NULL;
    gl_log_once("CoreServices: LSOpenCFURLRef -> not opened");
    return -10814;   // kLSApplicationNotFoundErr
}

// LongDateTime: seconds since 1904-01-01; CFAbsoluteTime: since 2001-01-01.
#define LDT_TO_CF 3061152000.0
OSStatus_ UCConvertCFAbsoluteTimeToLongDateTime(CFAbsoluteTime t, int64_t *ldt) { *ldt = (int64_t)(t + LDT_TO_CF); return 0; }
OSStatus_ UCConvertLongDateTimeToCFAbsoluteTime(int64_t ldt, CFAbsoluteTime *t) { *t = (double)ldt - LDT_TO_CF; return 0; }

// UCKeyTranslate: the input sources carry no key layout data (libglcarbon), so this cannot translate.
OSStatus_ UCKeyTranslate(const void *layout, uint16_t vk, uint16_t action, uint32_t mods, uint32_t kbType, uint32_t opts,
                         uint32_t *deadKeys, unsigned long maxLen, unsigned long *len, uint16_t *chars) {
    (void)layout; (void)vk; (void)action; (void)mods; (void)kbType; (void)opts; (void)deadKeys; (void)maxLen; (void)chars;
    if (len) *len = 0;
    gl_log_once("CoreServices: UCKeyTranslate -> paramErr");
    return -50;
}
