// The small GRID shims, one per library (built with -DGL_<NAME>, see Makefile):
//   libglavf     AVFoundation + AVCaptureScreenInput (macOS only; screen capture is never started)
//   libglcollab  Collaboration (macOS only): CBIdentity / CBIdentityAuthority finding no one
//   libglappsvc, libglsbridge   ApplicationServices, ScriptingBridge: linked by the game, no symbols imported
#import <Foundation/Foundation.h>
#include "glcommon.h"

#ifdef GL_AVF
@interface AVCaptureInput : NSObject @end
@interface AVCaptureScreenInput : AVCaptureInput @end
@implementation AVCaptureScreenInput GL_CATCHALL @end
#endif

#ifdef GL_COLLAB
@interface CBIdentityAuthority : NSObject @end
@implementation CBIdentityAuthority
GL_CATCHALL
+ (instancetype)defaultIdentityAuthority { return [self new]; }
+ (instancetype)localIdentityAuthority { return [self new]; }
@end
@interface CBIdentity : NSObject @end
@implementation CBIdentity
GL_CATCHALL
+ (instancetype)identityWithName:(NSString *)n authority:(id)a { (void)n; (void)a; return nil; }
@end
#endif

