// libglcarbon: Carbon for GRID Legends (libvxcarbon is empty). Text Input Sources answer "US keyboard, English";
// the Carbon event loop never has an event. UCKeyTranslate (in libglcs) fails without layout data, so the game falls
// back to its own key names.
#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>
#include "glcommon.h"

typedef int32_t OSStatus_;
typedef const void *TISInputSourceRef;

const CFStringRef kTISPropertyInputSourceID = CFSTR("TISPropertyInputSourceID");
const CFStringRef kTISPropertyInputSourceLanguages = CFSTR("TISPropertyInputSourceLanguages");
const CFStringRef kTISPropertyUnicodeKeyLayoutData = CFSTR("TISPropertyUnicodeKeyLayoutData");
const CFStringRef kTISNotifySelectedKeyboardInputSourceChanged = CFSTR("TISNotifySelectedKeyboardInputSourceChanged");

static CFDictionaryRef us_source(void) {
    static CFDictionaryRef d;
    if (!d) {
        CFStringRef langs1[] = { CFSTR("en") };
        CFArrayRef langs = CFArrayCreate(NULL, (const void **)langs1, 1, &kCFTypeArrayCallBacks);
        const void *k[] = { kTISPropertyInputSourceID, kTISPropertyInputSourceLanguages };
        const void *v[] = { CFSTR("com.apple.keylayout.US"), langs };
        d = CFDictionaryCreate(NULL, k, v, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFRelease(langs);
    }
    return d;
}
// (Copy functions: +1 as their names say)
static TISInputSourceRef copy_source(void) { gl_log_once("Carbon: TIS input source -> US"); return CFRetain(us_source()); }
TISInputSourceRef TISCopyCurrentKeyboardInputSource(void) { return copy_source(); }
TISInputSourceRef TISCopyCurrentKeyboardLayoutInputSource(void) { return copy_source(); }
TISInputSourceRef TISCopyCurrentASCIICapableKeyboardInputSource(void) { return copy_source(); }
TISInputSourceRef TISCopyCurrentASCIICapableKeyboardLayoutInputSource(void) { return copy_source(); }
void *TISGetInputSourceProperty(TISInputSourceRef s, CFStringRef key) {
    if (!s || CFGetTypeID(s) != CFDictionaryGetTypeID()) return NULL;
    return (void *)CFDictionaryGetValue((CFDictionaryRef)s, key);   // (no key layout data: NULL)
}
OSStatus_ TISSelectInputSource(TISInputSourceRef s) { (void)s; return 0; }

// ---- the Carbon event loop: never an event ----
enum { eventLoopTimedOutErr = -9875, eventNotHandledErr = -9874 };
OSStatus_ ReceiveNextEvent(uint32_t n, const void *list, double timeout, uint8_t pull, void **out) {
    (void)n; (void)list; (void)timeout; (void)pull;
    if (out) *out = NULL;
    return eventLoopTimedOutErr;
}
void *GetEventDispatcherTarget(void) { return NULL; }
OSStatus_ SendEventToEventTarget(void *e, void *t) { (void)e; (void)t; return eventNotHandledErr; }
void ReleaseEvent(void *e) { (void)e; }
OSStatus_ SetSystemUIMode(uint32_t mode, uint32_t options) { (void)mode; (void)options; return 0; }
uint8_t LMGetKbdType(void) { return 40; }   // (an ANSI keyboard)
