// libglal: OpenAL for GRID Legends (visionOS has no OpenAL). First stage: no device. alcOpenDevice and
// alcCaptureOpenDevice return NULL, as on a Mac with no audio output, so the game's OpenAL paths stay off. The game's
// sound goes through Wwise on CoreAudio, not OpenAL. Every entry point logs its first call, so a path that does need
// OpenAL shows up in the log (then: OpenAL Soft or an AVAudioEngine bridge).
#include <stddef.h>
#include <stdint.h>
#include "glcommon.h"

typedef int ALint; typedef unsigned ALuint; typedef int ALsizei; typedef int ALenum; typedef float ALfloat;
typedef char ALboolean; typedef char ALchar; typedef void ALvoid;
typedef void ALCdevice; typedef void ALCcontext; typedef int ALCint; typedef int ALCenum; typedef char ALCboolean;
typedef char ALCchar; typedef unsigned ALCuint; typedef int ALCsizei; typedef void ALCvoid;

#define AL_NO_ERROR 0
#define AL_INVALID_OPERATION 0xA004
#define ALC_INVALID_DEVICE 0xA001
#define L(name) gl_log_once("OpenAL: " name " (no device)")

static ALenum g_err = AL_NO_ERROR;
static ALenum fail(void) { g_err = AL_INVALID_OPERATION; return g_err; }

// ---- ALC ----
ALCdevice *alcOpenDevice(const ALCchar *n) { (void)n; L("alcOpenDevice -> NULL"); return NULL; }
ALCboolean alcCloseDevice(ALCdevice *d) { (void)d; return 0; }
ALCcontext *alcCreateContext(ALCdevice *d, const ALCint *a) { (void)d; (void)a; L("alcCreateContext -> NULL"); return NULL; }
void alcDestroyContext(ALCcontext *c) { (void)c; }
ALCboolean alcMakeContextCurrent(ALCcontext *c) { (void)c; return 0; }
ALCcontext *alcGetCurrentContext(void) { return NULL; }
ALCenum alcGetError(ALCdevice *d) { (void)d; return ALC_INVALID_DEVICE; }
ALCboolean alcIsExtensionPresent(ALCdevice *d, const ALCchar *e) { (void)d; (void)e; return 0; }
void *alcGetProcAddress(ALCdevice *d, const ALCchar *f) { (void)d; (void)f; return NULL; }
ALCenum alcGetEnumValue(ALCdevice *d, const ALCchar *e) { (void)d; (void)e; return 0; }
void alcGetIntegerv(ALCdevice *d, ALCenum p, ALCsizei n, ALCint *v) { (void)d; (void)p; for (ALCsizei i = 0; v && i < n; i++) v[i] = 0; }
ALCdevice *alcCaptureOpenDevice(const ALCchar *n, ALCuint f, ALCenum fmt, ALCsizei s) { (void)n; (void)f; (void)fmt; (void)s; L("alcCaptureOpenDevice -> NULL"); return NULL; }
ALCboolean alcCaptureCloseDevice(ALCdevice *d) { (void)d; return 0; }
void alcCaptureStart(ALCdevice *d) { (void)d; }
void alcCaptureStop(ALCdevice *d) { (void)d; }
void alcCaptureSamples(ALCdevice *d, ALCvoid *b, ALCsizei n) { (void)d; (void)b; (void)n; }

// ---- AL (without a current context every call is an invalid operation) ----
ALenum alGetError(void) { ALenum e = g_err; g_err = AL_NO_ERROR; return e; }
ALboolean alIsExtensionPresent(const ALchar *e) { (void)e; return 0; }
void *alGetProcAddress(const ALchar *f) { (void)f; return NULL; }
ALenum alGetEnumValue(const ALchar *e) { (void)e; return 0; }
ALfloat alGetFloat(ALenum p) { (void)p; fail(); return 0; }
void alGenBuffers(ALsizei n, ALuint *b) { for (ALsizei i = 0; b && i < n; i++) b[i] = 0; L("alGenBuffers"); fail(); }
void alDeleteBuffers(ALsizei n, const ALuint *b) { (void)n; (void)b; }
void alBufferData(ALuint b, ALenum f, const ALvoid *d, ALsizei s, ALsizei r) { (void)b; (void)f; (void)d; (void)s; (void)r; fail(); }
void alGenSources(ALsizei n, ALuint *s) { for (ALsizei i = 0; s && i < n; i++) s[i] = 0; L("alGenSources"); fail(); }
void alDeleteSources(ALsizei n, const ALuint *s) { (void)n; (void)s; }
void alSourcef(ALuint s, ALenum p, ALfloat v) { (void)s; (void)p; (void)v; fail(); }
void alSourcefv(ALuint s, ALenum p, const ALfloat *v) { (void)s; (void)p; (void)v; fail(); }
void alSourcei(ALuint s, ALenum p, ALint v) { (void)s; (void)p; (void)v; fail(); }
void alSource3i(ALuint s, ALenum p, ALint a, ALint b, ALint c) { (void)s; (void)p; (void)a; (void)b; (void)c; fail(); }
void alGetSourcei(ALuint s, ALenum p, ALint *v) { (void)s; (void)p; if (v) *v = 0; fail(); }
void alSourcePlay(ALuint s) { (void)s; fail(); }
void alSourcePause(ALuint s) { (void)s; fail(); }
void alSourceStop(ALuint s) { (void)s; fail(); }
void alSourceQueueBuffers(ALuint s, ALsizei n, const ALuint *b) { (void)s; (void)n; (void)b; fail(); }
void alSourceUnqueueBuffers(ALuint s, ALsizei n, ALuint *b) { (void)s; (void)n; (void)b; fail(); }
void alListenerfv(ALenum p, const ALfloat *v) { (void)p; (void)v; fail(); }
void alDistanceModel(ALenum m) { (void)m; fail(); }
void alDopplerFactor(ALfloat f) { (void)f; fail(); }
void alSpeedOfSound(ALfloat s) { (void)s; fail(); }
