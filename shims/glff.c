// libglff: ForceFeedback for GRID Legends (macOS only). The virtual pad's rumble (libgliokit's glrumble.m): the game's
// device for a virtual pad's stand-in service, and its Xbox 360 motor command (FFDeviceEscape) played on the pad's
// haptics. Effects are logged once each and refused. Any other service: no force feedback.
#include <stdint.h>
#include "glcommon.h"

typedef int32_t HRESULT_;
int32_t gl_ff_is(uint32_t service);
int32_t gl_ff_create(uint32_t service, void **out);
int32_t gl_ff_release(void *dev);
int32_t gl_ff_escape(void *dev, void *esc);
int32_t gl_ff_unsupported(const char *what);

HRESULT_ FFIsForceFeedback(uint32_t service) { return gl_ff_is(service); }
HRESULT_ FFCreateDevice(uint32_t service, void **dev) { return gl_ff_create(service, dev); }
HRESULT_ FFReleaseDevice(void *dev) { return gl_ff_release(dev); }
HRESULT_ FFDeviceEscape(void *dev, void *esc) { return gl_ff_escape(dev, esc); }
HRESULT_ FFDeviceGetForceFeedbackCapabilities(void *dev, void *caps) { (void)dev; (void)caps; return gl_ff_unsupported("FFDeviceGetForceFeedbackCapabilities"); }
HRESULT_ FFDeviceCreateEffect(void *dev, const void *uuid, void *eff, void **out) { (void)dev; (void)uuid; (void)eff; if (out) *out = NULL; return gl_ff_unsupported("FFDeviceCreateEffect"); }
HRESULT_ FFDeviceReleaseEffect(void *dev, void *eff) { (void)dev; (void)eff; return 0; }
HRESULT_ FFEffectDownload(void *eff) { (void)eff; return gl_ff_unsupported("FFEffectDownload"); }
HRESULT_ FFEffectGetEffectStatus(void *eff, uint32_t *status) { (void)eff; if (status) *status = 0; return gl_ff_unsupported("FFEffectGetEffectStatus"); }
HRESULT_ FFEffectSetParameters(void *eff, void *p, uint32_t flags) { (void)eff; (void)p; (void)flags; return gl_ff_unsupported("FFEffectSetParameters"); }
HRESULT_ FFEffectStart(void *eff, uint32_t it, uint32_t flags) { (void)eff; (void)it; (void)flags; return gl_ff_unsupported("FFEffectStart"); }
HRESULT_ FFEffectStop(void *eff) { (void)eff; return gl_ff_unsupported("FFEffectStop"); }
