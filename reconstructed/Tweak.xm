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

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    [[GLTController sharedController] start];
}

%end

// ---------------------------------------------------------------------------
// SBVolumeControl — replace the system volume HUD with the pill
// ---------------------------------------------------------------------------

%hook SBVolumeControl

- (void)_presentVolumeHUDWithVolume:(float)volume {
    GLTPrefs *prefs = [GLTPrefs sharedPrefs];
    if (prefs.enabled && prefs.replaceVolumeHUD) {
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

// ---------------------------------------------------------------------------
// SBNotificationBannerDestination — divert banners into the pill
// ---------------------------------------------------------------------------

%hook SBNotificationBannerDestination

- (void)postNotificationRequest:(id)request {
    GLTPrefs *prefs = [GLTPrefs sharedPrefs];
    NSString *section = [request sectionIdentifier];

    if (!prefs.enabled || !prefs.replaceBanners || section.length == 0) {
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

// ---------------------------------------------------------------------------
// SBMediaController — MediaRemote now-playing notifications
// ---------------------------------------------------------------------------
// All three hooks have the same shape: let SpringBoard finish first, then ask
// GLTMedia to re-read the now-playing dictionary.

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
static void glt_applyUpdate(id self, SEL _cmd, id update, id displayItem) {
    ((void (*)(id, SEL, id, id))glt_orig_applyUpdate)(self, _cmd, update, displayItem);

    GLTController *controller = [GLTController sharedController];
    [controller registerClockView:[self timeView] dateView:[self dateView]];
    [controller registerClockView:[self shortTimeView] dateView:nil];
}

// While Glint is drawing into a label the system must not overwrite it, but the
// intended text is kept so the label can be restored later.
static void glt_setText(id self, SEL _cmd, NSString *text) {
    if ([GLTClock isStyled:self] && [GLTClock isRendering]) {
        [GLTClock setSystemText:text forLabel:self];
        return;
    }
    ((GLTSetObjectIMP)glt_orig_setText)(self, _cmd, text);
}

static void glt_setAttributedText(id self, SEL _cmd, NSAttributedString *text) {
    if ([GLTClock isStyled:self] && [GLTClock isRendering]) {
        [GLTClock setSystemText:text.string forLabel:self];
        return;
    }
    ((GLTSetObjectIMP)glt_orig_setAttributedText)(self, _cmd, text);
}

// The system also recolours the label on every layout pass; that would defeat
// the configured pill text colour.
static void glt_setTextColor(id self, SEL _cmd, UIColor *color) {
    if ([GLTClock isStyled:self] && [GLTClock isRendering]) {
        return;
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

%ctor {
    Class timeItem   = objc_getClass("STUIStatusBarTimeItem");
    Class stringView = objc_getClass("STUIStatusBarStringView");

    if (!timeItem)   timeItem   = objc_getClass("_UIStatusBarTimeItem");
    if (!stringView) stringView = objc_getClass("_UIStatusBarStringView");

    if (!timeItem || !stringView) {
        return;
    }

    MSHookMessageEx(timeItem, @selector(applyUpdate:toDisplayItem:),
                    (IMP)&glt_applyUpdate, &glt_orig_applyUpdate);

    MSHookMessageEx(stringView, @selector(setText:),
                    (IMP)&glt_setText, &glt_orig_setText);
    MSHookMessageEx(stringView, @selector(setAttributedText:),
                    (IMP)&glt_setAttributedText, &glt_orig_setAttributedText);
    MSHookMessageEx(stringView, @selector(setTextColor:),
                    (IMP)&glt_setTextColor, &glt_orig_setTextColor);
    MSHookMessageEx(stringView, @selector(intrinsicContentSize),
                    (IMP)&glt_intrinsicContentSize, &glt_orig_intrinsicContentSize);
    MSHookMessageEx(stringView, @selector(sizeThatFits:),
                    (IMP)&glt_sizeThatFits, &glt_orig_sizeThatFits);
    MSHookMessageEx(stringView, @selector(drawTextInRect:),
                    (IMP)&glt_drawTextInRect, &glt_orig_drawTextInRect);
    MSHookMessageEx(stringView, @selector(layoutSubviews),
                    (IMP)&glt_layoutSubviews, &glt_orig_layoutSubviews);
    MSHookMessageEx(stringView, @selector(setCenter:),
                    (IMP)&glt_setCenter, &glt_orig_setCenter);
    MSHookMessageEx(stringView, @selector(setFrame:),
                    (IMP)&glt_setFrame, &glt_orig_setFrame);
    MSHookMessageEx(stringView, @selector(setAlpha:),
                    (IMP)&glt_setAlpha, &glt_orig_setAlpha);
    MSHookMessageEx(stringView, @selector(setHidden:),
                    (IMP)&glt_setHidden, &glt_orig_setHidden);
    MSHookMessageEx(stringView, @selector(didMoveToWindow),
                    (IMP)&glt_didMoveToWindow, &glt_orig_didMoveToWindow);
}
