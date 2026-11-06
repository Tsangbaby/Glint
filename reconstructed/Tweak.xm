// Tweak.xm — Glint 1.6.3 hook layer (reconstructed)
//
// Every hook below was recovered from the tweak constructor at 0x4000 in
// Glint.dylib. The constructor is a straight sequence of
// objc_getClass + MSHookMessageEx; the table in Glint_逆向分析报告.md lists the
// original replacement-function address and orig-slot for each entry.
//
// The status-bar pair is hooked by resolved Class pointer rather than by name,
// because the original probes for the modern spelling and falls back to the
// underscore-prefixed one (Glint.dylib 0x4128–0x4180).

#import <substrate.h>
#import "Glint.h"

// ---------------------------------------------------------------------------
// SpringBoard — bring the overlay up once the home screen is ready
// ---------------------------------------------------------------------------

%group GLTStartup
%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    [[GLTController sharedController] start];
}

%end
%end

// ---------------------------------------------------------------------------
// SBVolumeControl — replace the system volume HUD with the pill
// ---------------------------------------------------------------------------

%group GLTVolume
%hook SBVolumeControl

- (void)_presentVolumeHUDWithVolume:(float)volume {
    GLTPrefs *prefs = [GLTPrefs sharedPrefs];
    if (prefs.enabled && prefs.replaceVolumeHUD && [[GLTController sharedController] canPresentOverlay]) {
        [[GLTController sharedController] showVolume:volume];
        return;
    }
    %orig;
}

// Pass-through: the original keeps the default HUD stack construction. The
// swizzle exists so the class is touched once at load, before the volume hook
// above can fire.
- (instancetype)initWithHUDController:(id)hud
                        ringerControl:(id)ringer
                    telephonyManager:(id)telephony
                  conferenceManager:(id)conference {
    return %orig;
}

%end
%end

// ---------------------------------------------------------------------------
// SBNotificationBannerDestination — divert banners into the pill
// ---------------------------------------------------------------------------

%group GLTNotifications
%hook SBNotificationBannerDestination

- (void)postNotificationRequest:(id)request {
    GLTPrefs *prefs = [GLTPrefs sharedPrefs];
    if (!prefs.enabled || !prefs.replaceBanners ||
        ![[GLTController sharedController] canPresentOverlay] ||
        !GLTMethodMatches([request class], @selector(sectionIdentifier), @encode(id), @[]) ||
        !GLTMethodMatches([request class], @selector(content), @encode(id), @[])) {
        %orig;
        return;
    }
    NSString *section = [request sectionIdentifier];
    id content = [request content];
    if (![section isKindOfClass:[NSString class]] || section.length == 0 ||
        !GLTMethodMatches([content class], @selector(header), @encode(id), @[]) ||
        !GLTMethodMatches([content class], @selector(title), @encode(id), @[]) ||
        !GLTMethodMatches([content class], @selector(message), @encode(id), @[])) {
        %orig;
        return;
    }

    GLTNotification *notification = [GLTNotification new];
    notification.bundleIdentifier = section;

    Class appController = objc_getClass("SBApplicationController");
    id app = [[appController sharedInstance] applicationWithBundleIdentifier:section];
    NSString *name = [app displayName];

    if (name) {
        notification.appName = name;
    } else {
        // Fall back to the notification's own header ("Messages", "Mail", …)
        notification.appName = [[request content] header];
    }

    notification.icon = [UIImage _applicationIconImageForBundleIdentifier:section
                                                                  format:2
                                                                   scale:[UIScreen mainScreen].scale];
    notification.title = [[request content] title];
    notification.message = [[request content] message];

    [[GLTController sharedController] showNotification:notification];
}

%end
%end

// ---------------------------------------------------------------------------
// SBMediaController — MediaRemote now-playing notifications
// ---------------------------------------------------------------------------
// All three hooks have the same shape: let SpringBoard finish first, then ask
// GLTMedia to re-read the now-playing dictionary.

%group GLTMediaHooks
%hook SBMediaController

- (void)_mediaRemoteNowPlayingInfoDidChange:(id)change {
    %orig;
    [[GLTMedia sharedMedia] mediaDidChange];
}

- (void)_mediaRemoteNowPlayingApplicationIsPlayingDidChange:(id)change {
    %orig;
    [[GLTMedia sharedMedia] mediaDidChange];
}

- (void)_mediaRemoteNowPlayingApplicationDidChange:(id)change {
    %orig;
    [[GLTMedia sharedMedia] mediaDidChange];
}

%end
%end

// ---------------------------------------------------------------------------
// Status bar — the clock label becomes the pill host
// ---------------------------------------------------------------------------
// Hooking by resolved Class pointer, exactly like the original: probe the
// modern class first, else the legacy one, then install the same IMPs on
// whichever object we ended up with.

static IMP glt_orig_applyUpdate;
static IMP glt_orig_setText;
static IMP glt_orig_setAttributedText;
static IMP glt_orig_setTextColor;
static IMP glt_orig_intrinsicContentSize;
static IMP glt_orig_sizeThatFits;
static IMP glt_orig_drawTextInRect;
static IMP glt_orig_layoutSubviews;
static IMP glt_orig_setCenter;
static IMP glt_orig_setFrame;
static IMP glt_orig_setAlpha;
static IMP glt_orig_setHidden;
static IMP glt_orig_didMoveToWindow;

typedef void (*GLTSetObjectIMP)(id, SEL, id);
typedef void (*GLTSetBoolIMP)(id, SEL, BOOL);
typedef void (*GLTSetFloatIMP)(id, SEL, CGFloat);
typedef void (*GLTSetPointIMP)(id, SEL, CGPoint);
typedef void (*GLTSetRectIMP)(id, SEL, CGRect);
typedef CGSize (*GLTSizeIMP)(id, SEL);
typedef void (*GLTDrawTextIMP)(id, SEL, CGRect);

// applyUpdate:toDisplayItem: — the time item exposes the labels we draw into.
// timeView / dateView are the wide (date-style) pair, shortTimeView is the
// narrow "9:41" label used when the status bar is compact.
static id glt_applyUpdate(id self, SEL _cmd, id update, id displayItem) {
    id original = ((id (*)(id, SEL, id, id))glt_orig_applyUpdate)(self, _cmd, update, displayItem);

    GLTController *controller = [GLTController sharedController];
    id<GLTStatusBarTimeItem> item = (id<GLTStatusBarTimeItem>)self;
    UIView *time = GLTMethodMatches([self class], @selector(timeView), @encode(id), @[]) ? [item timeView] : nil;
    UIView *date = GLTMethodMatches([self class], @selector(dateView), @encode(id), @[]) ? [item dateView] : nil;
    UIView *shortTime = GLTMethodMatches([self class], @selector(shortTimeView), @encode(id), @[]) ? [item shortTimeView] : nil;
    [controller registerClockView:time dateView:date];
    [controller registerClockView:shortTime dateView:nil];
    return original;
}

// While Glint is drawing into a label the system must not overwrite it, but the
// intended text is kept so the label can be restored later.
static void glt_setText(id self, SEL _cmd, NSString *text) {
    if ([GLTClock isStyled:self] && ![GLTClock isRendering]) {
        [GLTClock setSystemText:text forLabel:self];
        return;
    }
    ((GLTSetObjectIMP)glt_orig_setText)(self, _cmd, text);
}

static void glt_setAttributedText(id self, SEL _cmd, NSAttributedString *text) {
    if ([GLTClock isStyled:self] && ![GLTClock isRendering]) {
        [GLTClock setSystemText:text.string forLabel:self];
        return;
    }
    ((GLTSetObjectIMP)glt_orig_setAttributedText)(self, _cmd, text);
}

// The system also recolours the label on every layout pass; that would defeat
// the configured pill text colour.
static void glt_setTextColor(id self, SEL _cmd, UIColor *color) {
    if ([GLTClock isStyled:self] && ![GLTClock isRendering]) {
        [GLTClock setSystemTextColor:color forLabel:self];
        color = [GLTClock foregroundColorForLabel:self];
    }
    ((GLTSetObjectIMP)glt_orig_setTextColor)(self, _cmd, color);
}

// Grow the label by the pill padding so the background view has room for the
// icon, the text and the badge.
static CGSize glt_intrinsicContentSize(id self, SEL _cmd) {
    CGSize size = ((GLTSizeIMP)glt_orig_intrinsicContentSize)(self, _cmd);
    if ([GLTClock isStyled:self]) {
        UIEdgeInsets padding = [GLTClock paddingForLabel:self];
        size.width  += padding.left + padding.right;
        size.height += padding.top + padding.bottom;
    }
    return size;
}

static CGSize glt_sizeThatFits(id self, SEL _cmd, CGSize proposed) {
    CGSize fitted = ((CGSize (*)(id, SEL, CGSize))glt_orig_sizeThatFits)(self, _cmd, proposed);
    if ([GLTClock isStyled:self]) {
        UIEdgeInsets padding = [GLTClock paddingForLabel:self];
        fitted.width  += padding.left + padding.right;
        fitted.height += padding.top + padding.bottom;
    }
    return fitted;
}

static void glt_drawTextInRect(id self, SEL _cmd, CGRect rect) {
    if ([GLTClock isStyled:self]) {
        UIColor *color = [GLTClock foregroundColorForLabel:self];
        if (![[(UILabel *)self textColor] isEqual:color]) {
            ((GLTSetObjectIMP)glt_orig_setTextColor)(self, @selector(setTextColor:), color);
        }
        UIEdgeInsets padding = [GLTClock paddingForLabel:self];
        rect.origin.x    += padding.left;
        rect.origin.y    += padding.top;
        rect.size.width  -= padding.left + padding.right;
        rect.size.height -= padding.top + padding.bottom;
    }
    ((GLTDrawTextIMP)glt_orig_drawTextInRect)(self, _cmd, rect);
}

// Every geometry change has to move the background view with the label; the
// companion label (the date under the time) is kept in sync as well.
static void glt_relayout(id self) {
    [GLTClock layoutBackgroundOfLabel:self];
    [GLTClock layoutBackgroundOfLabel:[GLTClock ownerOfLabel:self]];
}

static void glt_layoutSubviews(id self, SEL _cmd) {
    ((void (*)(id, SEL))glt_orig_layoutSubviews)(self, _cmd);
    glt_relayout(self);
}

static void glt_setCenter(id self, SEL _cmd, CGPoint center) {
    ((GLTSetPointIMP)glt_orig_setCenter)(self, _cmd, center);
    glt_relayout(self);
}

static void glt_setFrame(id self, SEL _cmd, CGRect frame) {
    ((GLTSetRectIMP)glt_orig_setFrame)(self, _cmd, frame);
    glt_relayout(self);
}

static void glt_setAlpha(id self, SEL _cmd, CGFloat alpha) {
    ((GLTSetFloatIMP)glt_orig_setAlpha)(self, _cmd, alpha);
    glt_relayout(self);
}

static void glt_setHidden(id self, SEL _cmd, BOOL hidden) {
    ((GLTSetBoolIMP)glt_orig_setHidden)(self, _cmd, hidden);
    glt_relayout(self);
}

static void glt_didMoveToWindow(id self, SEL _cmd) {
    ((void (*)(id, SEL))glt_orig_didMoveToWindow)(self, _cmd);
    glt_relayout(self);
}

#define GLT_TYPE(type) [NSString stringWithUTF8String:@encode(type)]

%ctor {
    Class springBoard = objc_getClass("SpringBoard");
    if (GLTMethodMatches(springBoard, @selector(applicationDidFinishLaunching:), @encode(void), @[@"@"])) {
        %init(GLTStartup);
    }
    Class volume = objc_getClass("SBVolumeControl");
    if (GLTMethodMatches(volume, @selector(_presentVolumeHUDWithVolume:), @encode(void), @[GLT_TYPE(float)]) &&
        GLTMethodMatches(volume, @selector(initWithHUDController:ringerControl:telephonyManager:conferenceManager:),
                         @encode(id), @[@"@", @"@", @"@", @"@"])) {
        %init(GLTVolume);
    }
    Class notifications = objc_getClass("SBNotificationBannerDestination");
    if (GLTMethodMatches(notifications, @selector(postNotificationRequest:), @encode(void), @[@"@"])) {
        %init(GLTNotifications);
    }
    Class media = objc_getClass("SBMediaController");
    if (GLTMethodMatches(media, @selector(_mediaRemoteNowPlayingInfoDidChange:), @encode(void), @[@"@"]) &&
        GLTMethodMatches(media, @selector(_mediaRemoteNowPlayingApplicationIsPlayingDidChange:), @encode(void), @[@"@"]) &&
        GLTMethodMatches(media, @selector(_mediaRemoteNowPlayingApplicationDidChange:), @encode(void), @[@"@"])) {
        %init(GLTMediaHooks);
    }

    Class timeItem = objc_getClass("STUIStatusBarTimeItem");
    Class stringView = objc_getClass("STUIStatusBarStringView");
    if (!timeItem) timeItem = objc_getClass("_UIStatusBarTimeItem");
    if (!stringView) stringView = objc_getClass("_UIStatusBarStringView");

    // Admit the whole status-bar surface before installing any of its hooks.
    BOOL ready = GLTMethodMatches(timeItem, @selector(applyUpdate:toDisplayItem:), @encode(id), @[@"@", @"@"]) &&
        GLTMethodMatches(stringView, @selector(setText:), @encode(void), @[@"@"]) &&
        GLTMethodMatches(stringView, @selector(setAttributedText:), @encode(void), @[@"@"]) &&
        GLTMethodMatches(stringView, @selector(setTextColor:), @encode(void), @[@"@"]) &&
        GLTMethodMatches(stringView, @selector(intrinsicContentSize), @encode(CGSize), @[]) &&
        GLTMethodMatches(stringView, @selector(sizeThatFits:), @encode(CGSize), @[GLT_TYPE(CGSize)]) &&
        GLTMethodMatches(stringView, @selector(drawTextInRect:), @encode(void), @[GLT_TYPE(CGRect)]) &&
        GLTMethodMatches(stringView, @selector(layoutSubviews), @encode(void), @[]) &&
        GLTMethodMatches(stringView, @selector(setCenter:), @encode(void), @[GLT_TYPE(CGPoint)]) &&
        GLTMethodMatches(stringView, @selector(setFrame:), @encode(void), @[GLT_TYPE(CGRect)]) &&
        GLTMethodMatches(stringView, @selector(setAlpha:), @encode(void), @[GLT_TYPE(CGFloat)]) &&
        GLTMethodMatches(stringView, @selector(setHidden:), @encode(void), @[GLT_TYPE(BOOL)]) &&
        GLTMethodMatches(stringView, @selector(didMoveToWindow), @encode(void), @[]);
    if (!ready) return;

    MSHookMessageEx(timeItem, @selector(applyUpdate:toDisplayItem:),
                    (IMP)&glt_applyUpdate, &glt_orig_applyUpdate);
    MSHookMessageEx(stringView, @selector(setText:), (IMP)&glt_setText, &glt_orig_setText);
    MSHookMessageEx(stringView, @selector(setAttributedText:), (IMP)&glt_setAttributedText, &glt_orig_setAttributedText);
    MSHookMessageEx(stringView, @selector(setTextColor:), (IMP)&glt_setTextColor, &glt_orig_setTextColor);
    MSHookMessageEx(stringView, @selector(intrinsicContentSize), (IMP)&glt_intrinsicContentSize, &glt_orig_intrinsicContentSize);
    MSHookMessageEx(stringView, @selector(sizeThatFits:), (IMP)&glt_sizeThatFits, &glt_orig_sizeThatFits);
    MSHookMessageEx(stringView, @selector(drawTextInRect:), (IMP)&glt_drawTextInRect, &glt_orig_drawTextInRect);
    MSHookMessageEx(stringView, @selector(layoutSubviews), (IMP)&glt_layoutSubviews, &glt_orig_layoutSubviews);
    MSHookMessageEx(stringView, @selector(setCenter:), (IMP)&glt_setCenter, &glt_orig_setCenter);
    MSHookMessageEx(stringView, @selector(setFrame:), (IMP)&glt_setFrame, &glt_orig_setFrame);
    MSHookMessageEx(stringView, @selector(setAlpha:), (IMP)&glt_setAlpha, &glt_orig_setAlpha);
    MSHookMessageEx(stringView, @selector(setHidden:), (IMP)&glt_setHidden, &glt_orig_setHidden);
    MSHookMessageEx(stringView, @selector(didMoveToWindow), (IMP)&glt_didMoveToWindow, &glt_orig_didMoveToWindow);
    GLTSetStatusBarHooksReady(YES);
}
