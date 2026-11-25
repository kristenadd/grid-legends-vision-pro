// grid_splash.m: the window's splash while the game starts - the "Splash" image (from tools/vxmac_grid.py build --splash,
// copied into the app at build time; none: the splash is plain) on white with "Loading..." under it, until the game's
// first frame with something on it (its first video; the frames before are black), then faded out.
//
//   grid_splash_show(view)       from the window controller's layout (grid_profile.m), once
//   grid_splash_frame(cb, tex)   from host.m's present hook (tools/sync_host.py), every frame until the splash is gone:
//                                every 6th frame is read back and every 8th pixel of every 8th row looked at
// The title screen's song ("SplashMusic", from the game's soundbanks: tools/vxmac_grid.py build) loops while it shows and
// fades out with it.
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Metal/Metal.h>

void vxmac_log(const char *fmt, ...);

static UIView *g_splash;
static int g_done, g_checking;   // (__atomic builtins)
static unsigned long g_n;
static double g_shown;
static AVAudioPlayer *g_music;

static void hide(const char *why) {
    if (__atomic_exchange_n(&g_done, 1, __ATOMIC_SEQ_CST)) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *v = g_splash; g_splash = nil;
        vxmac_log("GRID: splash off (%s, %.1f s after it showed)", why, CACurrentMediaTime() - g_shown);
        AVAudioPlayer *m = g_music; g_music = nil;
        if (m) {
            [m setVolume:0 fadeDuration:0.4];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 450 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [m stop]; });
        }
        [UIView animateWithDuration:0.4 animations:^{ v.alpha = 0; } completion:^(BOOL f) { (void)f; [v removeFromSuperview]; }];
    });
}

// (the art fills most of the window's height and sits on its bottom edge, so the black silhouette runs off it; it is
//  framed on what matters in the key art - the logo at 11-37 % of its width, the helmet ending at 78 % - and "Loading..."
//  goes under the logo. With another image: centred, the label under it. With "SplashText" too (tools/make_loading.swift:
//  the title screen and "LOADING" in the game's font, the same size): both fill the window, and the text pulses.)
@interface GridSplashView : UIView
@property UIImageView *art, *text;
@property UILabel *label;
@end
@implementation GridSplashView
- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize b = self.bounds.size, ls = [self.label sizeThatFits:CGSizeMake(b.width, 100)];
    UIImage *img = self.art.image;
    if (self.text) { self.art.frame = self.bounds; self.text.frame = self.bounds; return; }
    if (!img) { self.label.frame = CGRectMake((b.width - ls.width) / 2, (b.height - ls.height) / 2, ls.width, ls.height); return; }
    double ar = img.size.width / img.size.height, h = b.height * 0.78, w = h * ar;
    if (ar > 2.5) {   // (the wide key art)
        double x = b.width / 2 - w * (0.115 + 0.78) / 2, y = b.height - h;
        self.art.frame = CGRectMake(x, y, w, h);
        // (the helmet is cut by the image's top edge: the art's top fades into the white)
        CAGradientLayer *m = (CAGradientLayer *)self.art.layer.mask;
        if (![m isKindOfClass:[CAGradientLayer class]]) {
            m = [CAGradientLayer layer];
            m.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.blackColor.CGColor];
            m.locations = @[@0.0, @0.16];
            self.art.layer.mask = m;
        }
        m.frame = self.art.bounds;
        self.label.frame = CGRectMake(x + w * 0.245 - ls.width / 2, y + h * 0.70, ls.width, ls.height);
    } else {
        if (w > b.width) { w = b.width; h = w / ar; }
        self.art.frame = CGRectMake((b.width - w) / 2, (b.height - h) / 2 - 24, w, h);
        self.label.frame = CGRectMake((b.width - ls.width) / 2, CGRectGetMaxY(self.art.frame) + 16, ls.width, ls.height);
    }
}
@end

void grid_splash_show(UIView *root) {
    if (g_splash || g_done) return;
    GridSplashView *s = [[GridSplashView alloc] initWithFrame:root.bounds];
    s.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    s.backgroundColor = UIColor.whiteColor;   // (the key art's own background)
    s.clipsToBounds = YES;
    s.layer.zPosition = 100;   // (over the game's Metal layer, which the host adds to the same view later)
    s.userInteractionEnabled = NO;
    UIImage *img = [UIImage imageNamed:@"Splash"], *word = [UIImage imageNamed:@"SplashText"];
    s.art = [[UIImageView alloc] initWithImage:img];
    s.art.contentMode = UIViewContentModeScaleAspectFill;
    [s addSubview:s.art];
    UIView *pulsing;
    if (img && word) {
        s.text = [[UIImageView alloc] initWithImage:word];
        s.text.contentMode = UIViewContentModeScaleAspectFill;
        [s addSubview:s.text];
        pulsing = s.text;
    } else {
        UILabel *label = [UILabel new];
        label.text = @"Loading...";
        label.textColor = [UIColor colorWithWhite:0.25 alpha:1];
        label.font = [UIFont systemFontOfSize:30 weight:UIFontWeightSemibold];
        s.label = label;
        [s addSubview:label];
        pulsing = label;
    }
    // (a slow pulse, so it reads as working)
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"opacity"];
    a.fromValue = @1; a.toValue = @0.35; a.duration = 0.9; a.autoreverses = YES; a.repeatCount = HUGE_VALF;
    [pulsing.layer addAnimation:a forKey:@"pulse"];
    [root addSubview:s];
    g_splash = s; g_shown = CACurrentMediaTime();
    NSDataAsset *song = [[NSDataAsset alloc] initWithName:@"SplashMusic"];
    if (song) {
        NSError *err = nil;
        g_music = [[AVAudioPlayer alloc] initWithData:song.data error:&err];
        g_music.numberOfLoops = -1;   // (the song loops whole, as the game plays it)
        if (![g_music play]) { vxmac_log("GRID: splash music did not play: %s", err.localizedDescription.UTF8String ?: "?"); g_music = nil; }
    }
    vxmac_log("GRID: splash on (%s)", img && word ? "the loading screen" : img ? "with the Splash image" : "no Splash image in the app: plain");
    // (never stuck: off after 3 minutes whatever the frames say)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 180 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ hide("timeout"); });
}

void grid_splash_frame(void *cbp, void *texp) {
    if (__atomic_load_n(&g_done, __ATOMIC_SEQ_CST) || g_n++ % 6 || __atomic_load_n(&g_checking, __ATOMIC_SEQ_CST)) return;
    id<MTLCommandBuffer> cb = (__bridge id<MTLCommandBuffer>)cbp;
    id<MTLTexture> t = (__bridge id<MTLTexture>)texp;
    if (t.pixelFormat != MTLPixelFormatBGRA8Unorm && t.pixelFormat != MTLPixelFormatBGRA8Unorm_sRGB) { hide("first frame"); return; }
    NSUInteger w = t.width, h = t.height, row = w * 4;
    id<MTLBuffer> b = [cb.device newBufferWithLength:row * h options:MTLResourceStorageModeShared];
    if (!b) return;
    __atomic_store_n(&g_checking, 1, __ATOMIC_SEQ_CST);
    id<MTLBlitCommandEncoder> e = [cb blitCommandEncoder];
    [e copyFromTexture:t sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(w, h, 1)
              toBuffer:b destinationOffset:0 destinationBytesPerRow:row destinationBytesPerImage:row * h];
    [e endEncoding];
    [cb addCompletedHandler:^(id<MTLCommandBuffer> c) {
        (void)c;
        const uint8_t *p = b.contents;
        unsigned long lit = 0, n = 0;
        for (NSUInteger y = 0; y < h; y += 8)
            for (NSUInteger x = 0; x < w; x += 8, n++) {
                const uint8_t *q = p + y * row + x * 4;
                if (q[0] + 2 * q[1] + q[2] > 4 * 40) lit++;
            }
        if (n && lit * 100 > n) hide("the game's first picture");   // (over 1 % of the frame lit)
        __atomic_store_n(&g_checking, 0, __ATOMIC_SEQ_CST);
    }];
}
