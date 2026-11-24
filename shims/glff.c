// libglff: ForceFeedback for GRID Legends (macOS only). No force-feedback devices: FFIsForceFeedback says no
// interface, so the game never creates a device. (Gamepad rumble comes later through GameController haptics.)
#include <stdint.h>
#include "glcommon.h"

typedef int32_t HRESULT_;
#define FFERR_NOINTERFACE ((HRESULT_)0x80004002)
#define FFERR_UNSUPPORTED ((HRESULT_)0x80004001)

HRESULT_ FFIsForceFeedback(uint32_t service) { (void)service; return FFERR_NOINTERFACE; }
HRESULT_ FFCreateDevice(uint32_t service, void **dev) { (void)service; if (dev) *dev = NULL; gl_log_once("ForceFeedback: FFCreateDevice -> unsupported"); return FFERR_NOINTERFACE; }
HRESULT_ FFReleaseDevice(void *dev) { (void)dev; return 0; }
HRESULT_ FFDeviceGetForceFeedbackCapabilities(void *dev, void *caps) { (void)dev; (void)caps; return FFERR_UNSUPPORTED; }
HRESULT_ FFDeviceCreateEffect(void *dev, const void *uuid, void *eff, void **out) { (void)dev; (void)uuid; (void)eff; if (out) *out = NULL; return FFERR_UNSUPPORTED; }
HRESULT_ FFDeviceReleaseEffect(void *dev, void *eff) { (void)dev; (void)eff; return 0; }
HRESULT_ FFDeviceEscape(void *dev, void *esc) { (void)dev; (void)esc; return FFERR_UNSUPPORTED; }
HRESULT_ FFEffectDownload(void *eff) { (void)eff; return FFERR_UNSUPPORTED; }
HRESULT_ FFEffectGetEffectStatus(void *eff, uint32_t *status) { (void)eff; if (status) *status = 0; return FFERR_UNSUPPORTED; }
HRESULT_ FFEffectSetParameters(void *eff, void *p, uint32_t flags) { (void)eff; (void)p; (void)flags; return FFERR_UNSUPPORTED; }
HRESULT_ FFEffectStart(void *eff, uint32_t it, uint32_t flags) { (void)eff; (void)it; (void)flags; return FFERR_UNSUPPORTED; }
HRESULT_ FFEffectStop(void *eff) { (void)eff; return FFERR_UNSUPPORTED; }
