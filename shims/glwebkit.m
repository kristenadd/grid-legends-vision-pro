// libglwebkit: WebKit for GRID Legends. Re-exports WebKit (WKWebView is used as it is) and replaces the legacy WebView
// family (WebView, WebScriptObject, WebUndefined) with inert stand-ins. Feral's CFeralNSWebView subclasses WebView;
// on visionOS that is WebKitLegacy, which only works on its own web thread set up by UIKit, and creating one from the
// game's thread crashed in WebCore. The stand-in is a plain NSView (libvxkit) that loads nothing: legacy pages do not
// show. Only the game binds to this library, so WebKit's own classes are untouched for everything else.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include "glcommon.h"

@interface NSResponder : NSObject @end
@interface NSView : NSResponder
- (instancetype)initWithFrame:(CGRect)f;
@end

@interface WebView : NSView @end
@implementation WebView
GL_CATCHALL
- (instancetype)initWithFrame:(CGRect)f frameName:(NSString *)frame groupName:(NSString *)group {
    gl_log_once("WebKit: legacy WebView -> inert stand-in (its pages do not load)");
    return [super initWithFrame:f];
}
@end
@interface WebScriptObject : NSObject @end
@implementation WebScriptObject GL_CATCHALL @end
@interface WebUndefined : NSObject @end
@implementation WebUndefined
GL_CATCHALL
+ (instancetype)undefined { static WebUndefined *u; static dispatch_once_t o; dispatch_once(&o, ^{ u = [self new]; }); return u; }
@end
