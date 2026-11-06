//
//  GLTController.m
//
//  The state machine: one overlay window, one touch target over the clock, one
//  card at a time, plus the transient volume / notification
//  states that temporarily take over the pill.
//
//  Recovered from 0x504c…0xb648.
//

#import "Glint.h"
#import "GlintPrivate.h"

// Haptic + timer tuning, all read out of the original.
static const NSTimeInterval kGLTTickInterval = 1.0;
static const NSTimeInterval kGLTPlatterSpringDamping = 0.72;
static const CGFloat kGLTPlatterOpenDuration = 0.6;
static const CGFloat kGLTPlatterCloseDuration = 0.6;

// The status-bar time slot is ~9pt wide per character; the touch target is
// padded beyond the pill so it stays comfortable.

@implementation GLTController

#pragma mark - Singleton

+ (GLTController *)sharedController {
    static GLTController *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[GLTController alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    _clockViews = [NSHashTable weakObjectsHashTable];
    _dateViews = [NSHashTable weakObjectsHashTable];
    _pendingNotifications = [NSMutableArray array];
    return self;
}

#pragma mark - Startup

- (void)start {
    if (_window) return;

    UIWindowScene *scene = nil;
    for (UIScene *candidate in [UIApplication sharedApplication].connectedScenes) {
        if (![candidate isKindOfClass:[UIWindowScene class]]) continue;
        if ([(UIWindowScene *)candidate screen] == [UIScreen mainScreen]) {
            scene = (UIWindowScene *)candidate;
            break;
        }
    }

    _window = [[GLTWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _window.windowLevel = UIWindowLevelStatusBar;
    _window.backgroundColor = [UIColor clearColor];

    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = [UIColor clearColor];
    _window.rootViewController = root;

    [self moveWindowToScene:scene];

    _touchView = [UIView new];
    _touchView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.001];
    _touchView.layer.cornerCurve = kCACornerCurveContinuous;

    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(clockTapped)];
    [_touchView addGestureRecognizer:tap];

    UILongPressGestureRecognizer *press =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(clockLongPressed:)];
    press.minimumPressDuration = 0.45;
    [_touchView addGestureRecognizer:press];

    [root.view addSubview:_touchView];

    _timeFormatter = [NSDateFormatter new];
    [self updateFormatters];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(keyboardFrameChanged:)
                   name:UIKeyboardWillChangeFrameNotification object:nil];
    [center addObserver:self selector:@selector(keyboardFrameChanged:)
                   name:UIKeyboardWillHideNotification object:nil];
    [center addObserver:self selector:@selector(sourcesChanged:)
                   name:GLTSourcesDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(sourcesChanged:)
                   name:GLTLockStateDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(prefsChanged)
                   name:GLTPrefsDidChangeNotification object:nil];

    [[GLTMedia sharedMedia] mediaDidChange];
    if ([GLTPrefs sharedPrefs].enabled && [self currentPill] == GLTPillAlarm) {
        [[GLTClockItems sharedItems] refresh];
    }

    _timer = [NSTimer scheduledTimerWithTimeInterval:kGLTTickInterval
                                              target:self
                                            selector:@selector(tick)
                                            userInfo:nil
                                             repeats:YES];

    [self prefsChanged];
}

- (void)dealloc {
    [_timer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)moveWindowToScene:(UIWindowScene *)scene {
    if (scene) {
        _window.windowScene = scene;
    }
    _window.frame = [UIScreen mainScreen].bounds;
    _window.hidden = NO;
    [self layoutTouchView];
}

- (void)updateFormatters {
    NSLocale *locale = [NSLocale currentLocale];
    _timeFormatter.dateFormat =
        [NSDateFormatter dateFormatFromTemplate:(GLTPrefs.sharedPrefs.showSeconds ? @"jmmss" : @"jmm")
                                        options:0
                                         locale:locale];
}

#pragma mark - Notifications

- (void)keyboardFrameChanged:(NSNotification *)note {
    CGRect frame = CGRectZero;
    if (![note.name isEqualToString:UIKeyboardWillHideNotification]) {
        frame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
        frame = [[UIScreen mainScreen].coordinateSpace convertRect:frame toCoordinateSpace:_window.coordinateSpace];
    }
    _window.keyboardFrame = frame;
    _window.acceptsKeyboard = !CGRectIsEmpty(frame);
}

- (void)sourcesChanged:(NSNotification *)note {
    // Only the Weather provider may replace its already-open content. Keeping
    // the shell and callback owners avoids closing/reopening unrelated cards.
    if ([note.object isKindOfClass:[GLTWeather class]] &&
        _weatherPlatterContent && _platterView.content == _weatherPlatterContent) {
        GLTPlatterContent *previous = _weatherPlatterContent;
        GLTPlatterContent *content = GLTMakeWeatherPlatter();
        content.closeHandler = previous.closeHandler;
        content.resizeHandler = previous.resizeHandler;
        _weatherPlatterContent = content;
        _platterView.content = content;
        [self fitPlatterToContent];
    }
    [self update];
}

- (void)prefsChanged {
    [self updateFormatters];

    GLTPrefs *prefs = [GLTPrefs sharedPrefs];
    if (!prefs.enabled) {
        [self closePlatterAnimated:YES];
        [self hidePicker];
    }

    if ([self wantsWeather]) {
        [[GLTWeather sharedWeather] refreshForcing:YES];
    }

    [self update];
}

#pragma mark - Tick

- (void)tick {
    GLTPrefs *prefs = [GLTPrefs sharedPrefs];
    if (!prefs.enabled || GLTDeviceIsLocked()) {
        [self update];
        return;
    }

    if ([self wantsWeather]) {
        [[GLTWeather sharedWeather] refreshForcing:NO];
    }
    if ([self currentPill] == GLTPillAlarm) {
        [[GLTClockItems sharedItems] refresh];
    }

    [self update];
}

- (BOOL)wantsWeather {
    GLTPrefs *prefs = [GLTPrefs sharedPrefs];
    if (!prefs.enabled) return NO;
    return prefs.pill == GLTPillWeather;
}

#pragma mark - Transient states

- (void)showVolume:(float)volume {
    if (![self canPresentOverlay]) return;
    _volume = volume;
    _volumeUntil = [NSDate dateWithTimeIntervalSinceNow:[GLTPrefs sharedPrefs].volumeDuration];
    [self update];
    [self updateAfter:[GLTPrefs sharedPrefs].volumeDuration];
}

- (BOOL)showsVolume {
    return _volumeUntil && [_volumeUntil timeIntervalSinceNow] > 0;
}

- (void)showNotification:(GLTNotification *)notification {
    if (![self canPresentOverlay]) return;
    if ([self showsNotification]) {
        [_pendingNotifications addObject:notification];
        return;
    }

    _notification = notification;
    _notificationUntil = [NSDate dateWithTimeIntervalSinceNow:[GLTPrefs sharedPrefs].notificationDuration];

    UIImpactFeedbackGenerator *haptic =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];

    [self update];
    [self updateAfter:[GLTPrefs sharedPrefs].notificationDuration];
}

- (BOOL)showsNotification {
    return _notificationUntil && [_notificationUntil timeIntervalSinceNow] > 0;
}

- (void)updateAfter:(double)delay {
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [weakSelf update];
    });
}

#pragma mark - State resolution

- (NSInteger)currentPill {
    GLTPrefs *prefs = [GLTPrefs sharedPrefs];
    if (prefs.showMediaWhilePlaying) {
        GLTMedia *media = [GLTMedia sharedMedia];
        if ([media isPlaying] && [media hasMedia]) {
            return GLTPillNowPlaying;
        }
    }
    return (NSInteger)prefs.pill;
}

- (void)update {
    if (GLTDeviceIsLocked() || ![GLTPrefs sharedPrefs].enabled) {
        _notification = nil;
        _notificationUntil = nil;
        [_pendingNotifications removeAllObjects];
        [self closePlatterAnimated:NO];
        [self hidePicker];
    }
    if (_notification && ![self showsNotification]) {
        _notification = nil;
        if (_pendingNotifications.count) {
            GLTNotification *next = _pendingNotifications.firstObject;
            [_pendingNotifications removeObjectAtIndex:0];
            [self showNotification:next];
        }
    }

    [self renderClocks];
}

- (void)registerClockView:(UIView *)view dateView:(UIView *)dateView {
    if (![view isKindOfClass:[UILabel class]]) return;

    [_clockViews addObject:view];
    if (dateView) {
        [_dateViews addObject:dateView];
        [GLTClock setCompanion:dateView forLabel:view];
    }
    [self renderClocks];
}

- (BOOL)canPresentOverlay {
    return _window && _window.windowScene && !_window.hidden && GLTStatusBarHooksReady() &&
        [GLTPrefs sharedPrefs].enabled && !GLTDeviceIsLocked() && [self visibleClock] != nil;
}

- (UIView *)visibleClock {
    for (UIView *view in _clockViews) {
        if (!view.window || view.hidden || view.alpha < 0.5) continue;
        if (CGRectGetWidth(view.bounds) <= 0) continue;
        return view;
    }
    return nil;
}

- (CGRect)frameOfClock:(UIView *)clock {
    if (!clock) return CGRectZero;

    UIView *host = _window.rootViewController.view;
    CGRect frame = [clock convertRect:clock.bounds toView:host];
    double outset = [GLTClock outsetForLabel:clock];
    return CGRectInset(frame, -outset, -outset);
}

- (BOOL)showsPlainTime {
    if ([self showsVolume] || [self showsNotification]) return NO;
    return [self currentPill] == GLTPillTime;
}

#pragma mark - Rendering

- (void)renderClocks {
    if (!_window) return;

    GLTPrefs *prefs = [GLTPrefs sharedPrefs];
    BOOL admitted = prefs.enabled && GLTStatusBarHooksReady() && !GLTDeviceIsLocked();
    _window.hidden = !admitted;
    GLTPillContent *content = admitted ? [self pillContent] : nil;

    UIColor *background = prefs.backgroundColor;
    if (!background) {
        background = [UIColor colorWithWhite:0.06 alpha:0.72];
    }
    background = [background colorWithAlphaComponent:CGColorGetAlpha(background.CGColor) * prefs.backgroundOpacity];

    NSString *kind = [self shownKind];
    BOOL animated = (_shownKind != nil) && ![kind isEqualToString:_shownKind];
    _shownKind = content ? kind : nil;

    BOOL plain;

    if (content) {
        for (UILabel *label in _clockViews) {
            [GLTClock apply:content
                    toLabel:label
                 background:background
                  textColor:prefs.textColor
                   animated:animated];
        }
        plain = [self showsPlainTime];
    } else {
        [GLTClock restoreAllLabels];
        plain = YES;
    }

    CGFloat target = plain ? 1.0 : 0.0;
    for (UIView *label in _dateViews) {
        if (label.alpha == target) continue;

        if (animated || plain) {
            [UIView animateWithDuration:animated ? 0.25 : 0
                                  delay:animated ? 0.2 : 0
                                options:UIViewAnimationOptionBeginFromCurrentState
                             animations:^{
                label.alpha = target;
            } completion:nil];
        } else {
            [GLTClock fadeOutSnapshotOfLabel:label];
            label.alpha = 0;
        }

        [[GLTClock ownerOfLabel:label] invalidateIntrinsicContentSize];
        [[GLTClock ownerOfLabel:label].superview setNeedsLayout];
        [[GLTClock ownerOfLabel:label] setNeedsDisplay];
        [GLTClock layoutBackgroundOfLabel:[GLTClock ownerOfLabel:label]];
    }

    [self layoutTouchView];
}

// Identity of the current pill state; a change is what drives the cross-fade.
- (NSString *)shownKind {
    if ([self showsVolume]) return @"volume";
    if ([self showsNotification]) {
        return [NSString stringWithFormat:@"notification %p", _notification];
    }
    return [NSString stringWithFormat:@"pill %ld", (long)[self currentPill]];
}

#pragma mark - Pill content

- (GLTPillContent *)pillContent {
    if ([self showsVolume]) {
        long long percent = (long long)lroundf(_volume * 100.0f);
        NSString *symbol;
        NSString *text;

        if (percent <= 0) {
            symbol = @"speaker.slash.fill";
            text = GLTLocalizedString(@"Off");
        } else {
            symbol = percent < 34 ? @"speaker.wave.1.fill"
                   : percent < 67 ? @"speaker.wave.2.fill"
                                  : @"speaker.wave.3.fill";
            text = [NSString stringWithFormat:@"%lld%%", percent];
        }
        return [GLTPillContent contentWithSymbol:symbol text:text];
    }

    if ([self showsNotification]) {
        GLTPillContent *content = [GLTPillContent contentWithSymbol:@"app.badge.fill"
                                                               text:_notification.appName ?: @""];
        content.image = _notification.icon
            ?: GLTSymbol(@"app.badge.fill", 12, UIFontWeightSemibold);
        return content;
    }

    return [self contentForPill:[self currentPill]];
}

- (GLTPillContent *)contentForPill:(NSInteger)pill {
    switch (pill) {
        case GLTPillTime: {
            NSString *text = [_timeFormatter stringFromDate:[NSDate date]];
            return [GLTPillContent contentWithSymbol:nil text:text];
        }
        case GLTPillNowPlaying:
            return [self mediaContent];
        case GLTPillWeather:
            return [self weatherContent];
        case GLTPillAlarm:
            return [self alarmContent];
        case GLTPillStorage:
            return [self storageContent];
        case GLTPillQuickMessage:
            return [GLTPillContent contentWithSymbol:@"square.and.pencil" text:GLTLocalizedString(@"Message")];
        default:
            return [GLTPillContent new];
    }
}

- (GLTPillContent *)mediaContent {
    GLTMedia *media = [GLTMedia sharedMedia];
    if (![media hasMedia]) {
        return [GLTPillContent contentWithSymbol:@"music.note" text:GLTLocalizedString(@"Not Playing")];
    }

    UIWindow *host = _window;
    UIFont *font = [UIFont systemFontOfSize:12];
    (void)host;
    (void)font;

    GLTPillContent *content = [GLTPillContent contentWithSymbol:@"music.note"
                                                            text:[media title] ?: GLTLocalizedString(@"Not Playing")];
    double duration = [media duration];
    if (duration > 0) {
        content.progress = [media elapsed] / duration;
    }
    return content;
}

- (GLTPillContent *)weatherContent {
    GLTWeather *weather = [GLTWeather sharedWeather];
    if (!weather.hasData) {
        return [GLTPillContent contentWithSymbol:@"cloud.sun" text:@"--°"];
    }

    GLTPillContent *content = [GLTPillContent contentWithSymbol:nil
                                                            text:[GLTWeather temperatureString:weather.temperature]];
    content.image = GLTSymbol([GLTWeather symbolForCode:weather.code isDay:weather.isDay],
                              12, UIFontWeightSemibold);
    return content;
}

- (NSString *)stringForUpcomingDate:(NSDate *)date {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"EEEjmm"
                                                           options:0
                                                            locale:[NSLocale currentLocale]];
    return [formatter stringFromDate:date];
}

- (GLTPillContent *)alarmContent {
    GLTClockItems *items = [GLTClockItems sharedItems];

    if (items.timerFireDate) {
        double remaining = [items.timerFireDate timeIntervalSinceNow];
        if (remaining < 0) remaining = 0;

        long long total = (long long)remaining;
        long long hours = total / 3600;
        long long minutes = (total % 3600) / 60;
        long long seconds = total % 60;

        NSString *text = hours > 0
            ? [NSString stringWithFormat:@"%lld:%02lld:%02lld", hours, minutes, seconds]
            : [NSString stringWithFormat:@"%lld:%02lld", minutes, seconds];

        GLTPillContent *content = [GLTPillContent contentWithSymbol:@"timer" text:text];
        if (items.timerDuration > 0) {
            content.progress = 1.0 - (remaining / items.timerDuration);
        }
        return content;
    }

    GLTAlarm *alarm = items.alarms.firstObject;
    if (!alarm) {
        return [GLTPillContent contentWithSymbol:@"alarm" text:GLTLocalizedString(@"No alarms")];
    }

    return [GLTPillContent contentWithSymbol:@"alarm.fill"
                                        text:[self stringForUpcomingDate:alarm.fireDate]];
}

- (GLTPillContent *)storageContent {
    // Original 0x8740 uses only free storage, rounding above 10 decimal GB.
    NSDictionary *attributes = [[NSFileManager defaultManager]
                                attributesOfFileSystemForPath:@"/private/var" error:nil];
    long long free = [attributes[NSFileSystemFreeSize] longLongValue];
    if (free > 10000000000LL) {
        free = __builtin_llround((double)(unsigned long long)free / 1000000000.0) * 1000000000LL;
    }
    NSString *text = [NSByteCountFormatter stringFromByteCount:free
                                                 countStyle:NSByteCountFormatterCountStyleFile];
    return [GLTPillContent contentWithSymbol:@"internaldrive" text:text];
}

- (NSInteger)cutout {
    CGFloat top = _window.safeAreaInsets.top;
    if (top < 44.0) return 2;
    if (top < 51.0) return 1;
    return 0;
}

#pragma mark - Touch target

- (void)layoutTouchView {
    _touchView.hidden = ![self canPresentOverlay];
    if (_touchView.hidden) return;

    UIView *clock = [self visibleClock];
    if (!clock) {
        _touchView.hidden = YES;
        return;
    }
    _touchView.hidden = NO;

    CGRect frame = [self frameOfClock:clock];
    for (UIView *other in _clockViews) {
        if (!other.window || other.hidden || other.alpha < 0.5) continue;
        if (CGRectGetWidth(other.bounds) <= 0) continue;
        frame = CGRectUnion(frame, [self frameOfClock:other]);
    }

    // Grow the hit area downwards so a tap slightly under the clock still lands.
    frame.size.height = MAX(frame.size.height, 22);
    _anchorFrame = frame;

    _touchView.frame = frame;
    _touchView.layer.cornerRadius = CGRectGetHeight(frame) * 0.5;

}

#pragma mark - Cards

- (GLTPlatterContent *)platterContent {
    if ([self showsVolume]) return nil;
    if ([self showsNotification]) return GLTMakeNotificationPlatter(_notification);

    switch ([self currentPill]) {
        case GLTPillNowPlaying:
            return GLTMakeMediaPlatter();

        case GLTPillWeather: {
            [[GLTWeather sharedWeather] refreshForcing:NO];
            GLTPlatterContent *content = GLTMakeWeatherPlatter();
            _weatherPlatterContent = content;
            return content;
        }

        case GLTPillAlarm:
            [[GLTClockItems sharedItems] refresh];
            return GLTMakeClockPlatter();

        case GLTPillStorage:
            return GLTMakeStoragePlatter();

        case GLTPillQuickMessage:
            return GLTMakeComposePlatter();

        default:
            return nil;
    }
}

- (void)openPlatter:(GLTPlatterContent *)content {
    if (!content || _platterView || ![self canPresentOverlay]) return;

    UIView *host = _window.rootViewController.view;
    // clockTapped snapshots the anchor before popLabel can change its geometry.
    CGRect anchor = _anchorFrame;
    NSInteger cutout = [self cutout];
    CGFloat top = 6.0;
    CGFloat contentTop = 62.0;
    CGFloat cornerRadius = 44.0;
    if (cutout == 1) {
        contentTop = _window.safeAreaInsets.top + top;
        cornerRadius = 36.0;
    } else if (cutout == 2) {
        top = MAX(_window.safeAreaInsets.top, 20.0) + 4.0;
        contentTop = top + 18.0;
        cornerRadius = 22.0;
    }
    CGFloat topInset = contentTop - top;

    // Tap-outside dismissal layer.
    _dismissView = [[UIControl alloc] initWithFrame:host.bounds];
    _dismissView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.02];
    [_dismissView addTarget:self action:@selector(closePlatter) forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:_dismissView];

    CGFloat width = MIN(CGRectGetWidth(host.bounds) - 12.0, 400.0);
    GLTPlatterView *platter = [[GLTPlatterView alloc] initWithFrame:anchor];
    platter.openWidth = width;
    platter.topInset = topInset;

    // Install the content first: the handlers live on it.
    platter.content = content;

    __weak typeof(self) weakSelf = self;
    __weak GLTPlatterView *weakPlatter = platter;
    content.closeHandler = ^{
        GLTController *strongSelf = weakSelf;
        GLTPlatterView *currentPlatter = weakPlatter;
        if (!strongSelf || !currentPlatter || strongSelf->_platterView != currentPlatter) return;
        [strongSelf closePlatter];
    };
    content.resizeHandler = ^{
        GLTController *strongSelf = weakSelf;
        GLTPlatterView *currentPlatter = weakPlatter;
        if (!strongSelf || !currentPlatter || strongSelf->_platterView != currentPlatter) return;
        [strongSelf fitPlatterToContent];
    };

    CGFloat height = [platter heightForWidth:width];
    CGFloat centerX = CGRectGetMidX(anchor);
    // Preserve the original left-then-right clamp order in host coordinates.
    CGFloat x = centerX - width * 0.5;
    x = MAX(x, 6.0);
    CGFloat rightLimit = CGRectGetWidth(host.bounds) - 6.0 - width;
    x = MIN(x, rightLimit);
    CGRect openFrame = CGRectMake(x, top, width, height);
    // Keep one rounded clipping shell; its compact bounds clamp this radius.
    platter.layer.cornerRadius = cornerRadius;
    [platter layoutIfNeeded];
    [host addSubview:platter];
    _platterView = platter;

    content.alpha = 0;
    content.transform = CGAffineTransformScale(
        CGAffineTransformMakeTranslation(0, -14), 0.94, 0.94);

    [self layoutTouchView];

    if ([content wantsKeyboard]) {
        _previousKeyWindow = [UIApplication sharedApplication].keyWindow;
        [_window becomeKeyWindow];
        _window.acceptsKeyboard = YES;
    }

    UIImpactFeedbackGenerator *haptic =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];

    [UIView animateWithDuration:kGLTPlatterOpenDuration
                          delay:0
         usingSpringWithDamping:kGLTPlatterSpringDamping
          initialSpringVelocity:0.4
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        platter.frame = openFrame;
        [platter layoutIfNeeded];
    } completion:nil];

    [UIView animateWithDuration:0.55
                          delay:0.1
         usingSpringWithDamping:0.8
          initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        content.alpha = 1;
        content.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)closePlatter {
    [self closePlatterAnimated:YES];
}

- (void)closePlatterAnimated:(BOOL)animated {
    GLTPlatterView *platter = _platterView;
    if (!platter) return;

    CGRect anchor = _anchorFrame;
    _platterView = nil;
    platter.userInteractionEnabled = NO;
    platter.content.closeHandler = nil;
    platter.content.resizeHandler = nil;

    if (_window.acceptsKeyboard) {
        [_window endEditing:YES];
        _window.acceptsKeyboard = NO;
        [_previousKeyWindow makeKeyWindow];
        _previousKeyWindow = nil;
    }

    [_dismissView removeFromSuperview];
    _dismissView = nil;

    void (^cleanup)(BOOL) = ^(BOOL finished) {
        [platter removeFromSuperview];
        [self layoutTouchView];
    };

    if (!animated) {
        cleanup(YES);
        return;
    }

    // Critical damping avoids overshooting a large shell into a tiny pill.
    [UIView animateWithDuration:kGLTPlatterCloseDuration
                          delay:0
         usingSpringWithDamping:1.0
          initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        platter.frame = anchor;
        platter.layer.cornerRadius = CGRectGetHeight(anchor) * 0.5;
        [platter layoutIfNeeded];
        platter.content.alpha = 0;
        platter.content.transform = CGAffineTransformScale(
            CGAffineTransformMakeTranslation(0, -14), 0.94, 0.94);
    } completion:cleanup];
}

// A card whose height depends on its own content (the composer grows a line
// when the keyboard appears) tells the controller to re-measure.
- (void)fitPlatterToContent {
    GLTPlatterView *platter = _platterView;
    if (!platter) return;

    CGFloat width = platter.openWidth;
    // Ignore content callbacks until the shell has reached its expanded width.
    if (CGRectGetWidth(platter.frame) < width - 1.0) return;

    CGRect frame = platter.frame;
    frame.size.height = [platter heightForWidth:width];
    [UIView animateWithDuration:0.35
                          delay:0
         usingSpringWithDamping:0.85
          initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        platter.frame = frame;
        [platter layoutIfNeeded];
    } completion:nil];
}

#pragma mark - Tap handling

- (void)clockTapped {
    if (![self canPresentOverlay]) return;
    UIView *clock = [self visibleClock];
    if (!clock) return;

    _anchorFrame = [self frameOfClock:clock];
    [GLTClock popLabel:clock];

    GLTPlatterContent *content = [self platterContent];
    if (content) {
        [self openPlatter:content];
        return;
    }

    if ([self showsVolume]) return;

    GLTPrefs *prefs = [GLTPrefs sharedPrefs];
    if (!prefs.tapToCycle) return;

    NSArray *order = [GLTPrefs pillOrder];
    NSInteger pill = [self currentPill];
    NSUInteger index = [order indexOfObject:@(pill)];
    NSUInteger next = (index == NSNotFound || index + 1 >= order.count) ? 0 : index + 1;

    [prefs setPill:[order[next] integerValue]];

    if ([self wantsWeather]) {
        [[GLTWeather sharedWeather] refreshForcing:YES];
    }
    [self update];
}

- (void)clockLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    [self showPicker];
}

#pragma mark - Picker

// Single-row pill preview (the original keeps this variant for narrow layouts).
- (UIView *)pickerRowForPill:(NSInteger)pill font:(UIFont *)font {
    // Original arm64 0x9f7c: 34-point preview and an inline catalogue title.
    GLTPrefs *prefs = [GLTPrefs sharedPrefs];
    UIView *row = [UIView new];
    UIView *preview = [UIView new];
    preview.backgroundColor = prefs.backgroundColor ?: [UIColor colorWithWhite:0.06 alpha:0.85];
    preview.backgroundColor = [preview.backgroundColor colorWithAlphaComponent:CGColorGetAlpha(preview.backgroundColor.CGColor) * prefs.backgroundOpacity];
    preview.layer.cornerCurve = kCACornerCurveContinuous;
    preview.layer.cornerRadius = 17;
    if (prefs.pill == pill) {
        preview.layer.borderWidth = 2;
        preview.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.9].CGColor;
    }

    GLTPillContent *content = [self contentForPill:pill];
    UILabel *label = [UILabel new];
    label.attributedText = [content attributedStringWithFont:font color:prefs.textColor];
    [label sizeToFit];
    CGFloat previewWidth = ceil(CGRectGetWidth(label.bounds)) + 28;
    preview.frame = CGRectMake(0, 0, previewWidth, 34);
    label.center = CGPointMake(CGRectGetMidX(preview.bounds), CGRectGetMidY(preview.bounds));
    [preview addSubview:label];
    [row addSubview:preview];

    UILabel *name = [UILabel new];
    name.text = [GLTPrefs nameForPill:pill];
    name.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    name.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    name.layer.shadowColor = [UIColor blackColor].CGColor;
    name.layer.shadowOpacity = 0.4;
    name.layer.shadowRadius = 3;
    name.layer.shadowOffset = CGSizeZero;
    [name sizeToFit];
    name.center = CGPointMake(CGRectGetMaxX(preview.frame) + 10 + CGRectGetWidth(name.bounds) * 0.5, 17);
    [row addSubview:name];
    row.frame = CGRectMake(0, 0, CGRectGetMaxX(name.frame), 34);
    row.tag = pill;
    [row addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pickerRowTapped:)]];
    return row;
}

// Grid cell used by showPicker. Width is supplied by the grid layout.
- (UIView *)pickerCellForPill:(NSInteger)pill font:(UIFont *)font width:(CGFloat)width {
    // Original arm64 0xa4bc: only the preview is filled/outlined; the title is below it.
    GLTPrefs *prefs = [GLTPrefs sharedPrefs];
    UIView *cell = [UIView new];
    UIView *preview = [UIView new];
    preview.backgroundColor = prefs.backgroundColor ?: [UIColor colorWithWhite:0.06 alpha:0.85];
    preview.backgroundColor = [preview.backgroundColor colorWithAlphaComponent:CGColorGetAlpha(preview.backgroundColor.CGColor) * prefs.backgroundOpacity];
    preview.layer.cornerCurve = kCACornerCurveContinuous;
    preview.layer.cornerRadius = 17;
    if (prefs.pill == pill) {
        preview.layer.borderWidth = 2;
        preview.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.9].CGColor;
    }

    GLTPillContent *content = [self contentForPill:pill];
    UILabel *label = [UILabel new];
    label.attributedText = [content attributedStringWithFont:font color:prefs.textColor];
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.7;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.textAlignment = NSTextAlignmentCenter;
    [label sizeToFit];
    CGFloat previewWidth = MIN(ceil(CGRectGetWidth(label.bounds)), width - 24);
    preview.frame = CGRectMake((width - previewWidth - 24) * 0.5, 0, previewWidth + 24, 34);
    label.frame = CGRectMake(12, 0, previewWidth, 34);
    [preview addSubview:label];
    [cell addSubview:preview];

    UILabel *name = [UILabel new];
    name.text = [GLTPrefs nameForPill:pill];
    name.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    name.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    name.textAlignment = NSTextAlignmentCenter;
    name.adjustsFontSizeToFitWidth = YES;
    name.minimumScaleFactor = 0.8;
    name.layer.shadowColor = [UIColor blackColor].CGColor;
    name.layer.shadowOpacity = 0.4;
    name.layer.shadowRadius = 3;
    name.layer.shadowOffset = CGSizeZero;
    name.frame = CGRectMake(0, 38, width, 14);
    [cell addSubview:name];
    cell.frame = CGRectMake(0, 0, width, 52);
    cell.tag = pill;
    [cell addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pickerRowTapped:)]];
    return cell;
}

- (void)showPicker {
    if (![self canPresentOverlay] || _pickerView || _platterView) return;

    UIView *clock = [self visibleClock];
    if (!clock) return;

    UIImpactFeedbackGenerator *haptic =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];

    UIView *host = _window.rootViewController.view;
    CGRect anchor = [self frameOfClock:clock];

    _pickerView = [[UIView alloc] initWithFrame:host.bounds];
    _pickerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [host addSubview:_pickerView];

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:nil];
    blur.frame = _pickerView.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [blur addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hidePicker)]];
    [_pickerView addSubview:blur];

    GLTPickerList *list = [[GLTPickerList alloc] initWithFrame:CGRectZero];
    list.showsVerticalScrollIndicator = NO;
    list.clipsToBounds = NO;
    [_pickerView addSubview:list];

    UIFont *font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];

    CGFloat listTop = CGRectGetMaxY(anchor) + 14;
    CGFloat listHeight = CGRectGetHeight(host.bounds) - listTop - MAX(host.safeAreaInsets.bottom, 12);
    list.frame = CGRectMake(0, listTop, CGRectGetWidth(host.bounds), listHeight);
    list.alwaysBounceVertical = NO;
    [[GLTClockItems sharedItems] refresh];

    NSArray *order = [GLTPrefs pillOrder];
    NSMutableArray<UIView *> *cells = [NSMutableArray array];
    CGFloat contentHeight = order.count * 42 - 8;
    if (contentHeight <= MIN(CGRectGetHeight(list.bounds), CGRectGetHeight(host.bounds) * 0.8)) {
        for (NSUInteger i = 0; i < order.count; i++) {
            NSInteger pill = [order[i] integerValue];
            UIView *row = [self pickerRowForPill:pill font:font];
            CGFloat rowX = MIN(MAX(CGRectGetMinX(anchor), 12), CGRectGetWidth(host.bounds) - CGRectGetWidth(row.bounds) - 12);
            row.frame = CGRectMake(rowX, i * 42, CGRectGetWidth(row.bounds), CGRectGetHeight(row.bounds));
            [list addSubview:row];
            [cells addObject:row];
        }
    } else {
        CGFloat cellWidth = MIN((CGRectGetWidth(host.bounds) - 32 - 10) * 0.5, 190);
        CGFloat startX = (CGRectGetWidth(host.bounds) - cellWidth * 2 - 10) * 0.5;
        for (NSUInteger i = 0; i < order.count; i++) {
            NSInteger pill = [order[i] integerValue];
            UIView *cell = [self pickerCellForPill:pill font:font width:cellWidth];
            cell.frame = CGRectMake(startX + (i % 2) * (cellWidth + 10), (i / 2) * 64,
                                    CGRectGetWidth(cell.bounds), CGRectGetHeight(cell.bounds));
            [list addSubview:cell];
            [cells addObject:cell];
        }
        contentHeight = ((order.count + 1) / 2) * 64 - 12;
    }
    list.contentSize = CGSizeMake(CGRectGetWidth(list.bounds), contentHeight);

    CGPoint origin = [list convertPoint:CGPointMake(CGRectGetMidX(anchor), CGRectGetMidY(anchor)) fromView:host];
    for (NSUInteger current = 0; current < cells.count; current++) {
        UIView *cell = cells[current];
        cell.alpha = 0;
        CGAffineTransform scale = CGAffineTransformMakeScale(0.5, 0.5);
        CGAffineTransform translation = CGAffineTransformMakeTranslation(origin.x - cell.center.x, origin.y - cell.center.y);
        cell.transform = CGAffineTransformConcat(scale, translation);
        [UIView animateWithDuration:0.5
                              delay:0.025 * current
             usingSpringWithDamping:0.78
              initialSpringVelocity:0
                            options:UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            cell.alpha = 1;
            cell.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
    [UIView animateWithDuration:0.3 animations:^{
        blur.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    }];

    [self layoutTouchView];
}

- (void)pickerRowTapped:(UITapGestureRecognizer *)gesture {
    NSInteger pill = gesture.view.tag;

    UISelectionFeedbackGenerator *haptic = [UISelectionFeedbackGenerator new];
    [haptic selectionChanged];

    _volumeUntil = nil;
    _notificationUntil = nil;
    [[GLTPrefs sharedPrefs] setPill:pill];

    if ([self wantsWeather]) {
        [[GLTWeather sharedWeather] refreshForcing:NO];
    }

    [self hidePicker];
    [self update];
}

- (void)hidePicker {
    UIView *picker = _pickerView;
    if (!picker) return;

    _pickerView = nil;
    picker.userInteractionEnabled = NO;

    [UIView animateWithDuration:0.22
                     animations:^{
        picker.alpha = 0;
        for (UIView *subview in picker.subviews) {
            if ([subview isKindOfClass:[UIVisualEffectView class]]) {
                ((UIVisualEffectView *)subview).effect = nil;
            } else {
                subview.transform = CGAffineTransformMakeScale(0.9, 0.9);
            }
        }
    } completion:^(BOOL finished) {
        [picker removeFromSuperview];
    }];

    [self layoutTouchView];
}

@end
