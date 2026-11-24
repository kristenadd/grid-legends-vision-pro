// libglkit: AppKit for GRID Legends. Re-exports libvxkit (VXpro's AppKit stand-in) and adds what the game imports
// beyond it: NSApplicationMain, a few constants and the classes it names directly (alerts, panels, Touch Bar...).
// Nothing here draws: alerts are logged and answered with their first button.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdlib.h>
#include "glcommon.h"

// ---- constants ------------------------------------------------------------------------------------------------------
#define NOTE(n) NSString *const n = @#n;
NOTE(NSApplicationLaunchUserNotificationKey) NOTE(NSWindowDidResignMainNotification)
NOTE(NSWorkspaceActiveSpaceDidChangeNotification) NOTE(NSWorkspaceLaunchConfigurationArguments)
NSString *const NSPasteboardTypeString = @"public.utf8-plain-text";
NSString *const NSImageNameTouchBarPlayTemplate = @"NSTouchBarPlayTemplate";
NSString *const NSTouchBarItemIdentifierFixedSpaceLarge = @"NSTouchBarItemIdentifierFixedSpaceLarge";
NSString *const NSTouchBarItemIdentifierFixedSpaceSmall = @"NSTouchBarItemIdentifierFixedSpaceSmall";
NSString *const NSTouchBarItemIdentifierFlexibleSpace = @"NSTouchBarItemIdentifierFlexibleSpace";
NSString *const NSTouchBarItemIdentifierOtherItemsProxy = @"NSTouchBarItemIdentifierOtherItemsProxy";

void NSDisableScreenUpdates(void) {}
void NSEnableScreenUpdates(void) {}

// ---- NSApplicationMain ----------------------------------------------------------------------------------------------
// AppKit's version loads the main nib and runs the principal class. GRID's MainMenu.nib holds the menu bar and the
// application's delegate connection, so the nib is skipped: the principal class (Info.plist NSPrincipalClass,
// CFeralNSApplication) is made the shared application, its own delegate, and run. The game's own bundle is $GL_BUNDLE_PATH (set by the host; see glcf.c).
@interface NSApplication : NSObject
+ (instancetype)sharedApplication;
- (void)run;
- (id)delegate;
- (void)setDelegate:(id)d;
@end

int NSApplicationMain(int argc, const char *argv[]) {
    (void)argc; (void)argv;
    gl_set_program_thread();
    NSString *name = nil;
    const char *env = getenv("GL_PRINCIPAL_CLASS");
    if (env && *env) name = @(env);
    const char *bp = getenv("GL_BUNDLE_PATH");
    if (!name && bp) {
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[@(bp) stringByAppendingPathComponent:@"Contents/Info.plist"]];
        name = info[@"NSPrincipalClass"];
    }
    Class cls = name ? NSClassFromString(name) : Nil;
    if (!cls) { vxmac_log("GRID shim: NSApplicationMain: principal class %s not found, using NSApplication", name ? name.UTF8String : "(none)"); cls = [NSApplication class]; }
    vxmac_log("GRID shim: NSApplicationMain: %s (MainMenu.nib skipped)", class_getName(cls));
    NSApplication *app = [cls sharedApplication];
    // (the nib's one connection: the application is its own delegate - CFeralNSApplication implements
    //  applicationDidFinishLaunching:, which starts the game)
    if (![app delegate] && [app respondsToSelector:@selector(applicationDidFinishLaunching:)]) {
        [app setDelegate:app];
        vxmac_log("GRID shim: NSApplicationMain: %s is its own delegate (as MainMenu.nib connects it)", class_getName(cls));
    }
    [app run];
    return 0;
}

// ---- classes the game names directly ----------------------------------------------------------------------------------
@interface NSResponder : NSObject @end
@interface NSView : NSResponder
- (NSArray *)subviews;
- (void)addSubview:(NSView *)v;
- (void)removeFromSuperview;
@end

// -setSubviews: (libvxkit's NSView has subviews, addSubview: and removeFromSuperview, not this). Feral's views set their
// children with it and read them back (CFeralNSView rootView: subviews[0]). Only NSViews are taken: libvxkit's
// addSubview: writes NSView ivars, so anything else (a WKWebView is a UIView here) is logged and left out.
@implementation NSView (GLSubviews)
- (void)setSubviews:(NSArray *)views {
    for (NSView *v in [[self subviews] copy]) [v removeFromSuperview];
    for (id v in views) {
        if ([v isKindOfClass:[NSView class]]) [self addSubview:v];
        else { char m[200]; snprintf(m, sizeof m, "AppKit: setSubviews: skipped a %s (not an NSView)", class_getName([v class])); gl_log_once(m); }
    }
}
@end

typedef NSInteger NSModalResponse;
static const NSModalResponse kFirstButton = 1000;   // NSAlertFirstButtonReturn

@interface NSAlert : NSObject {
    NSString *_message, *_informative; NSMutableArray *_buttons; NSInteger _style;
}
@end
@implementation NSAlert
GL_CATCHALL
- (instancetype)init { if ((self = [super init])) _buttons = [NSMutableArray new]; return self; }
+ (instancetype)alertWithError:(NSError *)e { NSAlert *a = [self new]; a->_message = e.localizedDescription; return a; }
- (NSString *)messageText { return _message; }
- (void)setMessageText:(NSString *)s { _message = [s copy]; }
- (NSString *)informativeText { return _informative; }
- (void)setInformativeText:(NSString *)s { _informative = [s copy]; }
- (NSInteger)alertStyle { return _style; }
- (void)setAlertStyle:(NSInteger)s { _style = s; }
- (id)addButtonWithTitle:(NSString *)t { [_buttons addObject:t ?: @""]; return nil; }
- (NSArray *)buttons { return @[]; }
- (NSModalResponse)runModal {
    vxmac_log("GRID shim: NSAlert \"%s\" / \"%s\" buttons [%s] -> first button",
              _message.UTF8String ?: "", _informative.UTF8String ?: "", [_buttons componentsJoinedByString:@", "].UTF8String);
    return kFirstButton;
}
- (void)beginSheetModalForWindow:(id)w completionHandler:(void (^)(NSModalResponse))h {
    (void)w;
    NSModalResponse r = [self runModal];
    if (h) h(r);
}
@end

@interface NSSavePanel : NSObject @end
@implementation NSSavePanel
GL_CATCHALL
+ (instancetype)savePanel { return [self new]; }
- (NSModalResponse)runModal { gl_log_once("NSSavePanel/NSOpenPanel runModal -> cancel"); return 0; }
- (void)beginSheetModalForWindow:(id)w completionHandler:(void (^)(NSModalResponse))h { (void)w; if (h) h([self runModal]); }
- (NSURL *)URL { return nil; }
@end
@interface NSOpenPanel : NSSavePanel @end
@implementation NSOpenPanel
+ (instancetype)openPanel { return [self new]; }
- (NSArray *)URLs { return @[]; }
@end

// Pasteboard: an in-process string store (no system pasteboard on the program's side).
@interface NSPasteboard : NSObject { NSMutableDictionary *_items; } @end
@implementation NSPasteboard
GL_CATCHALL
+ (instancetype)generalPasteboard {
    static NSPasteboard *pb; static dispatch_once_t o;
    dispatch_once(&o, ^{ pb = [NSPasteboard new]; pb->_items = [NSMutableDictionary new]; });
    return pb;
}
- (NSInteger)clearContents { @synchronized (self) { [_items removeAllObjects]; } return 1; }
- (NSInteger)declareTypes:(NSArray *)t owner:(id)o { (void)t; (void)o; return [self clearContents]; }
- (BOOL)setString:(NSString *)s forType:(NSString *)t { @synchronized (self) { if (s && t) _items[t] = [s copy]; } return YES; }
- (NSString *)stringForType:(NSString *)t { @synchronized (self) { return t ? _items[t] : nil; } }
@end

@interface NSRunningApplication : NSObject @end
@implementation NSRunningApplication
GL_CATCHALL
+ (instancetype)currentApplication { static NSRunningApplication *a; static dispatch_once_t o; dispatch_once(&o, ^{ a = [self new]; }); return a; }
+ (NSArray *)runningApplicationsWithBundleIdentifier:(NSString *)b { (void)b; return @[]; }
- (pid_t)processIdentifier { return getpid(); }
- (BOOL)isActive { return YES; }
- (BOOL)activateWithOptions:(NSUInteger)o { (void)o; return YES; }
@end

@interface NSSound : NSObject @end
@implementation NSSound GL_CATCHALL @end
@interface NSGraphicsContext : NSObject @end
@implementation NSGraphicsContext GL_CATCHALL @end
@interface NSMenuItem : NSObject @end
@implementation NSMenuItem
GL_CATCHALL
+ (instancetype)separatorItem { return [self new]; }
@end

// (Touch Bar: built by the game, never shown)
@interface NSTouchBar : NSObject @end
@implementation NSTouchBar GL_CATCHALL @end
@interface NSTouchBarItem : NSObject @end
@implementation NSTouchBarItem GL_CATCHALL @end
@interface NSCustomTouchBarItem : NSTouchBarItem @end
@implementation NSCustomTouchBarItem GL_CATCHALL @end
@interface NSGroupTouchBarItem : NSTouchBarItem @end
@implementation NSGroupTouchBarItem GL_CATCHALL @end
@interface NSScrubberLayout : NSObject @end
@implementation NSScrubberLayout GL_CATCHALL @end
@interface NSScrubberFlowLayout : NSScrubberLayout @end
@implementation NSScrubberFlowLayout GL_CATCHALL @end

// (views: plain NSViews from libvxkit; the game subclasses NSScrubberItemView)
@interface NSImageView : NSView @end
@implementation NSImageView GL_CATCHALL @end
@interface NSTextField : NSView @end
@implementation NSTextField GL_CATCHALL @end
@interface NSProgressIndicator : NSView @end
@implementation NSProgressIndicator GL_CATCHALL @end
@interface NSScrubber : NSView @end
@implementation NSScrubber GL_CATCHALL @end
@interface NSScrubberArrangedView : NSView @end
@implementation NSScrubberArrangedView GL_CATCHALL @end
@interface NSScrubberItemView : NSScrubberArrangedView @end
@implementation NSScrubberItemView GL_CATCHALL @end

// ---- diagnostics: what the game shows in its web views (Feral's UI: dialogs are web pages snapshotted to textures) ---
static void gl_wk_log(const char *what, NSString *s) {
    NSString *one = [[s stringByReplacingOccurrencesOfString:@"\n" withString:@" "] stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    if (one.length > 600) one = [[one substringToIndex:600] stringByAppendingString:@"..."];
    vxmac_log("GRID: WKWebView %s: %s", what, one.UTF8String ?: "");
}
static IMP g_wk_req, g_wk_html, g_wk_file, g_wk_js;
static id wk_load_request(id self, SEL _cmd, NSURLRequest *r) { gl_wk_log("loadRequest", r.URL.absoluteString); return ((id (*)(id, SEL, id))g_wk_req)(self, _cmd, r); }
static id wk_load_html(id self, SEL _cmd, NSString *h, NSURL *b) { gl_wk_log("loadHTMLString", h); return ((id (*)(id, SEL, id, id))g_wk_html)(self, _cmd, h, b); }
static id wk_load_file(id self, SEL _cmd, NSURL *u, NSURL *rd) { gl_wk_log("loadFileURL", u.path); return ((id (*)(id, SEL, id, id))g_wk_file)(self, _cmd, u, rd); }
static void wk_eval(id self, SEL _cmd, NSString *js, id h) { gl_wk_log("evaluateJavaScript", js); ((void (*)(id, SEL, id, id))g_wk_js)(self, _cmd, js, h); }
__attribute__((constructor)) static void gl_wk_diag(void) {
    Class c = objc_getClass("WKWebView");
    if (!c) return;
    Method m;
    if ((m = class_getInstanceMethod(c, @selector(loadRequest:)))) g_wk_req = method_setImplementation(m, (IMP)wk_load_request);
    if ((m = class_getInstanceMethod(c, @selector(loadHTMLString:baseURL:)))) g_wk_html = method_setImplementation(m, (IMP)wk_load_html);
    if ((m = class_getInstanceMethod(c, @selector(loadFileURL:allowingReadAccessToURL:)))) g_wk_file = method_setImplementation(m, (IMP)wk_load_file);
    if ((m = class_getInstanceMethod(c, @selector(evaluateJavaScript:completionHandler:)))) g_wk_js = method_setImplementation(m, (IMP)wk_eval);
}
