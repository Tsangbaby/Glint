//
//  GLTController.m
//
//  The state machine: one overlay window, one touch target over the clock, one
//  card at a time, plus the transient volume / connection / notification
//  states that temporarily take over the pill.
//
//  Recovered from 0x504c…0xb648.
//

#import "Glint.h"
#import "GlintPrivate.h"
#import <ifaddrs.h>
#import <net/if.h>
#import <mach/mach.h>
#import <dlfcn.h>

// Haptic + timer tuning, all read out of the original.
static const NSTimeInterval kGLTTickInterval = 1.0;
static const NSTimeInterval kGLTPlatterSpringDamping = 0.78;
static const CGFloat kGLTPlatterOpenDuration = 0.42;
static const CGFloat kGLTPlatterCloseDuration = 0.24;

// The status-bar time slot is ~9pt wide per character; the touch target is
// padded beyond the pill so it stays comfortable.
static const CGFloat kGLTPlatterMinHeight = 44;

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
    _ticks = 0;
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
    _dateFormatter = [NSDateFormatter new];
    [self updateFormatters];

    [UIDevice currentDevice].batteryMonitoringEnabled = YES;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(keyboardFrameChanged:)
                   name:UIKeyboardWillChangeFrameNotification object:nil];
    [center addObserver:self selector:@selector(keyboardFrameChanged:)
                   name:UIKeyboardWillHideNotification object:nil];
    [center addObserver:self selector:@selector(batteryChanged)
                   name:UIDeviceBatteryLevelDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(batteryChanged)
                   name:UIDeviceBatteryStateDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(sourcesChanged)
                   name:GLTSourcesDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(sourcesChanged)
                   name:GLTLockStateDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(prefsChanged)
                   name:GLTPrefsDidChangeNotification object:nil];

    [GLTEvents sharedEvents];
    [GLTUnlocks sharedUnlocks];
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
    _dateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"EEEdMMM"
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

- (void)batteryChanged {
    [self update];
}

- (void)sourcesChanged {
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
    _ticks++;

    [self sampleNetwork];
    if (prefs.deviceConnections || [self currentPill] == GLTPillBattery) {
        [self checkDevices];
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
    return prefs.pill == GLTPillWeather || prefs.pill == GLTPillSun;
}

#pragma mark - Device connections

// Compare the current accessory list against the previous poll; announce a
// connection or a disconnect with a pill takeover.
- (void)checkDevices {
    NSArray<GLTDevice *> *devices = GLTConnectedDevices();
    NSMutableDictionary *current = [NSMutableDictionary dictionary];

    for (GLTDevice *device in devices) {
        if (!device.identifier) continue;
        current[device.identifier] = @(device.percent);
    }

    if ([GLTPrefs sharedPrefs].enabled && [GLTPrefs sharedPrefs].deviceConnections) {
        if (_knownDevices) {
            for (GLTDevice *device in devices) {
                if (device.internal) continue;
                id previous = _knownDevices[device.identifier];
                if (!previous) {
                    [self showConnection:device connected:YES];
                } else if ([previous longLongValue] != device.percent) {
                    [self showConnection:device connected:YES];
                }
            }
            for (NSString *identifier in _knownDevices) {
                BOOL present = NO;
                for (GLTDevice *device in devices) {
                    if ([device.identifier isEqualToString:identifier]) { present = YES; break; }
                }
                if (!present) {
                    GLTDevice *gone = [GLTDevice new];
                    gone.identifier = identifier;
                    gone.name = identifier;
                    [self showConnection:gone connected:NO];
                }
            }
        }
    }

    _knownDevices = current;
}

- (void)showConnection:(GLTDevice *)device connected:(BOOL)connected {
    _connectionDevice = device;
    _connectionConnected = connected;
    _connectionUntil = [NSDate dateWithTimeIntervalSinceNow:[GLTPrefs sharedPrefs].notificationDuration];

    UIImpactFeedbackGenerator *haptic =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];

    [self update];
    [self updateAfter:[GLTPrefs sharedPrefs].notificationDuration];
}

- (BOOL)showsConnection {
    return _connectionUntil && [_connectionUntil timeIntervalSinceNow] > 0;
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
    if ([self showsVolume] || [self showsNotification] || [self showsConnection]) return NO;
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
    if ([self showsConnection]) {
        return [NSString stringWithFormat:@"connection %@ %d",
                _connectionDevice.identifier ?: @"", _connectionConnected];
    }
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
            text = @"Off";
        } else {
            symbol = percent < 34 ? @"speaker.wave.1.fill"
                   : percent < 67 ? @"speaker.wave.2.fill"
                                  : @"speaker.wave.3.fill";
            text = [NSString stringWithFormat:@"%lld%%", percent];
        }
        return [GLTPillContent contentWithSymbol:symbol text:text];
    }

    if ([self showsConnection]) {
        GLTPillContent *content = [GLTPillContent new];
        content.image = _connectionConnected
            ? _connectionDevice.glyph
            : GLTSymbol(@"headphones", 12, UIFontWeightSemibold);
        content.imageTint = _connectionConnected ? nil : [UIColor systemRedColor];
        content.text = _connectionConnected
            ? GLTPercentText(_connectionDevice.percent)
            : @"Off";
        content.progress = _connectionConnected ? _connectionDevice.percent / 100.0 : 0;
        return content;
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
        case GLTPillDate: {
            NSString *text = [_dateFormatter stringFromDate:[NSDate date]];
            return [GLTPillContent contentWithSymbol:@"calendar" text:text];
        }
        case GLTPillBattery:
            return [self batteryContent];
        case GLTPillNetwork: {
            NSString *text = _networkText.length ? _networkText : @"↓0K ↑0K";
            return [GLTPillContent contentWithSymbol:nil text:text];
        }
        case GLTPillNowPlaying:
            return [self mediaContent];
        case GLTPillCalendar:
            return [self countContent:[self eventsLeftToday]
                             singular:@"event"
                               plural:@"events"
                                 none:@"No events"
                               symbol:@"calendar"];
        case GLTPillReminders:
            return [self countContent:(NSInteger)[GLTEvents sharedEvents].reminders.count
                             singular:@"reminder"
                               plural:@"reminders"
                                 none:@"All done"
                               symbol:@"checklist"];
        case GLTPillWeather:
            return [self weatherContent];
        case GLTPillAlarm:
            return [self alarmContent];
        case GLTPillNextEvent:
            return [self nextEventContent];
        case GLTPillSun:
            return [self sunContent];
        case GLTPillStorage:
            return [self storageContent];
        case GLTPillCountdown:
            return [self countdownContent];
        case GLTPillUnlocks: {
            long long today = [GLTUnlocks sharedUnlocks].today;
            NSString *text = [NSString stringWithFormat:(today == 1 ? @"%ld unlock" : @"%ld unlocks"),
                              (long)today];
            return [GLTPillContent contentWithSymbol:@"lock.open" text:text];
        }
        case GLTPillQuickMessage:
            return [GLTPillContent contentWithSymbol:@"square.and.pencil" text:@"Message"];
        default:
            return [GLTPillContent new];
    }
}

- (GLTPillContent *)batteryContent {
    GLTDevice *device = GLTConnectedDevices().firstObject;
    long long percent = device ? device.percent : -1;
    BOOL charging = device.charging;

    NSString *symbol;
    if (percent < 0) {
        symbol = @"battery.0";
    } else if (charging) {
        symbol = @"battery.100.bolt";
    } else if (percent <= 0) {
        symbol = @"battery.0";
    } else if (percent < 25) {
        symbol = @"battery.0";
    } else if (percent < 50) {
        symbol = @"battery.25";
    } else if (percent < 75) {
        symbol = @"battery.50";
    } else if (percent < 100) {
        symbol = @"battery.75";
    } else {
        symbol = @"battery.100";
    }

    GLTPillContent *content = [GLTPillContent contentWithSymbol:symbol text:GLTPercentText(percent)];
    if (percent >= 0 && percent <= 20 && !charging) {
        content.imageTint = [UIColor systemRedColor];
    } else if (charging) {
        content.imageTint = [UIColor systemGreenColor];
    }
    content.progress = percent >= 0 ? percent / 100.0 : 0;
    return content;
}

- (GLTPillContent *)mediaContent {
    GLTMedia *media = [GLTMedia sharedMedia];
    if (![media hasMedia]) {
        return [GLTPillContent contentWithSymbol:@"music.note" text:@"Not Playing"];
    }

    UIWindow *host = _window;
    UIFont *font = [UIFont systemFontOfSize:12];
    (void)host;
    (void)font;

    GLTPillContent *content = [GLTPillContent contentWithSymbol:@"music.note"
                                                            text:[media title] ?: @"Not Playing"];
    double duration = [media duration];
    if (duration > 0) {
        content.progress = [media elapsed] / duration;
    }
    return content;
}

- (GLTPillContent *)weatherContent {
    GLTWeather *weather = [GLTWeather sharedWeather];
    if (!weather.hasData) {
        return [GLTPillContent contentWithSymbol:@"cloud.sun" text:@"-"];
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
        return [GLTPillContent contentWithSymbol:@"alarm" text:@"No alarms"];
    }

    return [GLTPillContent contentWithSymbol:@"alarm.fill"
                                        text:[self stringForUpcomingDate:alarm.fireDate]];
}

- (GLTPillContent *)nextEventContent {
    NSArray<EKEvent *> *events = [GLTEvents sharedEvents].upcomingEvents;
    NSCalendar *calendar = [NSCalendar currentCalendar];

    for (EKEvent *event in events) {
        if ([event.endDate timeIntervalSinceNow] <= 0) continue;
        if (event.isAllDay) continue;

        BOOL today = [calendar isDateInToday:event.startDate];
        double minutes = [event.startDate timeIntervalSinceNow] / 60.0;

        NSString *when;
        if (minutes <= 0) {
            when = @"now";
        } else if (minutes < 60) {
            when = [NSString stringWithFormat:@"in %ld min", (long)minutes];
        } else if (today) {
            when = @"today";
        } else {
            when = @"tomorrow";
        }

        NSString *title = event.title.length > 18
            ? [[event.title substringToIndex:17] stringByAppendingString:@"…"]
            : (event.title ?: @"Event");

        GLTPillContent *content = [GLTPillContent contentWithSymbol:@"calendar"
                                                                text:[title stringByAppendingString:@" "]];
        content.text = [NSString stringWithFormat:@"%@ · %@", title, when];
        content.imageTint = [UIColor colorWithCGColor:event.calendar.CGColor];
        return content;
    }

    return [GLTPillContent contentWithSymbol:@"calendar" text:@"No events"];
}

- (GLTPillContent *)storageContent {
    return [GLTPillContent contentWithSymbol:@"internaldrive" text:GLTStorageSummary()];
}

- (GLTPillContent *)countdownContent {
    GLTPrefs *prefs = [GLTPrefs sharedPrefs];
    NSDate *target = prefs.countdownDate;
    if (!target) {
        return [GLTPillContent contentWithSymbol:@"hourglass" text:@"Set a date"];
    }

    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate *from = [calendar startOfDayForDate:[NSDate date]];
    NSDate *to = [calendar startOfDayForDate:target];
    NSInteger days = [[calendar components:NSCalendarUnitDay fromDate:from toDate:to options:0] day];

    NSString *text;
    if (days == 0) {
        text = @"today";
    } else if (days == 1) {
        text = @"1 day";
    } else if (days > 1) {
        text = [NSString stringWithFormat:@"%ld days", (long)days];
    } else if (days == -1) {
        text = @"1 day ago";
    } else {
        text = [NSString stringWithFormat:@"%ld days ago", (long)-days];
    }

    NSString *title = prefs.countdownTitle;
    if (title.length) {
        text = [NSString stringWithFormat:@"%@ · %@", title, text];
    }
    return [GLTPillContent contentWithSymbol:@"hourglass" text:text];
}

- (GLTPillContent *)sunContent {
    BOOL sunset = NO;
    NSDate *date = [[GLTWeather sharedWeather] nextSunEvent:&sunset];
    if (!date) {
        return [GLTPillContent contentWithSymbol:@"sunrise" text:@"--:--"];
    }

    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"jmm"
                                                           options:0
                                                            locale:[NSLocale currentLocale]];

    GLTPillContent *content = [GLTPillContent contentWithSymbol:(sunset ? @"sunset.fill" : @"sunrise.fill")
                                                            text:[formatter stringFromDate:date]];
    content.imageTint = [UIColor systemOrangeColor];
    return content;
}

- (NSInteger)eventsLeftToday {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSInteger count = 0;

    for (EKEvent *event in [GLTEvents sharedEvents].upcomingEvents) {
        if (![calendar isDateInToday:event.startDate]) continue;
        if ([event.endDate timeIntervalSinceNow] <= 0) continue;
        count++;
    }
    return count;
}

- (GLTPillContent *)countContent:(NSInteger)count
                        singular:(NSString *)singular
                          plural:(NSString *)plural
                            none:(NSString *)none
                          symbol:(NSString *)symbol
{
    NSString *text;
    if (count <= 0) {
        text = none;
        return [GLTPillContent contentWithSymbol:symbol text:text];
    }
    text = [NSString stringWithFormat:@"%ld %@", (long)count, count == 1 ? singular : plural];

    GLTPillContent *content = [GLTPillContent contentWithSymbol:symbol text:text];
    content.badge = count;
    return content;
}

#pragma mark - Network sampling

// Sum the byte counters on the Wi-Fi and cellular interfaces and turn the
// delta into a rate. getifaddrs is the only way to get this without private
// frameworks.
- (void)sampleNetwork {
    unsigned long long received = 0;
    unsigned long long sent = 0;

    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) == 0) {
        for (struct ifaddrs *entry = interfaces; entry != NULL; entry = entry->ifa_next) {
            if (!entry->ifa_addr || entry->ifa_addr->sa_family != AF_LINK) continue;

            NSString *name = [NSString stringWithUTF8String:entry->ifa_name];
            if (![name hasPrefix:@"en"] && ![name hasPrefix:@"pdp_ip"]) continue;

            struct if_data *data = (struct if_data *)entry->ifa_data;
            if (!data) continue;
            received += data->ifi_ibytes;
            sent     += data->ifi_obytes;
        }
        freeifaddrs(interfaces);
    }

    NSDate *now = [NSDate date];
    if (_lastNetworkDate && received >= _lastReceived && sent >= _lastSent) {
        double seconds = [now timeIntervalSinceDate:_lastNetworkDate];
        if (seconds > 0.2) {
            double down = (received - _lastReceived) / seconds;
            double up   = (sent - _lastSent) / seconds;
            _networkText = [NSString stringWithFormat:@"↓%@ ↑%@",
                            [self speed:down], [self speed:up]];
        }
    }

    _lastReceived = received;
    _lastSent = sent;
    _lastNetworkDate = now;
}

- (NSString *)speed:(double)bytesPerSecond {
    if (bytesPerSecond >= 1024.0 * 1024.0) {
        return [NSString stringWithFormat:@"%.1fM", bytesPerSecond / (1024.0 * 1024.0)];
    }
    return [NSString stringWithFormat:@"%.0fK", bytesPerSecond / 1024.0];
}

- (double)cutout {
    return _window.safeAreaInsets.top;
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
    if ([self showsConnection]) return GLTMakeDevicePlatter([self pillContent]);
    if ([self showsNotification]) return GLTMakeNotificationPlatter(_notification);

    switch ([self currentPill]) {
        case GLTPillDate:
        case GLTPillCalendar:
        case GLTPillNextEvent:
            return GLTMakeEventsPlatter();

        case GLTPillNowPlaying:
            return GLTMakeMediaPlatter();

        case GLTPillReminders:
            return GLTMakeRemindersPlatter();

        case GLTPillWeather:
        case GLTPillSun:
            [[GLTWeather sharedWeather] refreshForcing:YES];
            return GLTMakeWeatherPlatter();

        case GLTPillAlarm:
            [[GLTClockItems sharedItems] refresh];
            return GLTMakeClockPlatter();

        case GLTPillStorage:
            return GLTMakeStoragePlatter();

        case GLTPillCountdown:
            return GLTMakeCountdownPlatter();

        case GLTPillUnlocks:
            return GLTMakeUnlocksPlatter();

        case GLTPillQuickMessage:
            return GLTMakeComposePlatter();

        default:
            return nil;
    }
}

- (void)openPlatter:(GLTPlatterContent *)content {
    if (!content || _platterView || ![self canPresentOverlay]) return;

    UIView *host = _window.rootViewController.view;
    CGRect anchor = [self frameOfClock:[self visibleClock]];
    CGFloat screenWidth = CGRectGetWidth([UIScreen mainScreen].bounds);

    // Tap-outside dismissal layer.
    _dismissView = [[UIControl alloc] initWithFrame:host.bounds];
    _dismissView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.001];
    [_dismissView addTarget:self action:@selector(closePlatter) forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:_dismissView];

    CGFloat width = MIN(screenWidth - 24, 380);
    CGFloat top = [self cutout] + 6;

    GLTPlatterView *platter = [[GLTPlatterView alloc] initWithFrame:CGRectMake(0, top, width, 44)];
    platter.openWidth = width;
    platter.topInset = top;

    // Install the content first: the handlers live on it.
    platter.content = content;

    __weak typeof(self) weakSelf = self;
    content.closeHandler = ^{
        [weakSelf closePlatter];
    };
    content.resizeHandler = ^{
        [weakSelf fitPlatterToContent];
    };

    CGFloat height = [platter heightForWidth:width];
    CGFloat centerX = CGRectGetMidX(anchor);
    platter.frame = CGRectMake(centerX - width / 2, top, width, MAX(height, 44));
    platter.layer.cornerRadius = 22;
    [host addSubview:platter];
    _platterView = platter;

    // The card grows out of the pill: start small, slightly above, and spring in.
    platter.content.alpha = 0;
    platter.content.transform = CGAffineTransformConcat(
        CGAffineTransformMakeScale(0.92, 0.92),
        CGAffineTransformMakeTranslation(0, -14));

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
          initialSpringVelocity:0.6
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        platter.content.alpha = 1;
        platter.content.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)closePlatter {
    [self closePlatterAnimated:YES];
}

- (void)closePlatterAnimated:(BOOL)animated {
    GLTPlatterView *platter = _platterView;
    if (!platter) return;

    _platterView = nil;

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

    [UIView animateWithDuration:kGLTPlatterCloseDuration
                     animations:^{
        platter.content.alpha = 0;
        platter.content.transform = CGAffineTransformConcat(
            CGAffineTransformMakeScale(0.94, 0.94),
            CGAffineTransformMakeTranslation(0, -10));
    } completion:cleanup];
}

// A card whose height depends on its own content (the composer grows a line
// when the keyboard appears) tells the controller to re-measure.
- (void)fitPlatterToContent {
    GLTPlatterView *platter = _platterView;
    if (!platter) return;

    CGFloat width = platter.openWidth ?: CGRectGetWidth(platter.frame);
    CGFloat height = MAX([platter heightForWidth:width], kGLTPlatterMinHeight);

    [UIView animateWithDuration:0.32
                          delay:0
         usingSpringWithDamping:0.85
          initialSpringVelocity:0.4
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        CGRect frame = platter.frame;
        frame.size.height = height;
        platter.frame = frame;
        [platter layoutIfNeeded];
    } completion:nil];
}

#pragma mark - Tap handling

- (void)clockTapped {
    if (![self canPresentOverlay]) return;
    UIView *clock = [self visibleClock];
    if (!clock) return;

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
    GLTPrefs *prefs = [GLTPrefs sharedPrefs];

    UIView *row = [UIView new];
    row.backgroundColor = prefs.backgroundColor ?: [UIColor colorWithWhite:0.12 alpha:0.9];
    row.layer.cornerCurve = kCACornerCurveContinuous;
    row.layer.cornerRadius = 17;

    GLTPillContent *content = [self contentForPill:pill];
    NSAttributedString *string = [content attributedStringWithFont:font color:prefs.textColor];

    UILabel *label = [UILabel new];
    label.attributedText = string;
    label.textColor = prefs.textColor;
    [label sizeToFit];

    CGRect bounds = label.bounds;
    bounds.size.width  += 34;
    bounds.size.height  = MAX(bounds.size.height, 34);
    label.frame = CGRectMake(17, (bounds.size.height - CGRectGetHeight(label.bounds)) / 2,
                             CGRectGetWidth(label.bounds), CGRectGetHeight(label.bounds));

    UIView *container = [[UIView alloc] initWithFrame:bounds];
    container.backgroundColor = row.backgroundColor;
    container.layer.cornerRadius = 17;
    container.layer.cornerCurve = kCACornerCurveContinuous;
    [container addSubview:label];
    label.frame = CGRectMake(17, (CGRectGetHeight(bounds) - CGRectGetHeight(label.bounds)) / 2,
                             CGRectGetWidth(label.bounds), CGRectGetHeight(label.bounds));

    UILabel *name = [UILabel new];
    name.text = [GLTPrefs nameForPill:pill];
    name.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    name.textColor = [UIColor colorWithWhite:1 alpha:0.75];
    [name sizeToFit];
    name.frame = CGRectMake(0, CGRectGetMaxY(bounds) + 6, CGRectGetWidth(name.bounds), CGRectGetHeight(name.bounds));
    name.center = CGPointMake(CGRectGetMidX(bounds), name.center.y);

    UIView *wrapper = [[UIView alloc] initWithFrame:CGRectMake(0, 0,
        MAX(CGRectGetWidth(bounds), CGRectGetWidth(name.bounds)),
        CGRectGetMaxY(name.frame))];
    [wrapper addSubview:container];
    [wrapper addSubview:name];

    wrapper.tag = pill;
    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pickerRowTapped:)];
    [wrapper addGestureRecognizer:tap];
    return wrapper;
}

// Grid cell used by showPicker. Width is supplied by the grid layout.
- (UIView *)pickerCellForPill:(NSInteger)pill font:(UIFont *)font width:(CGFloat)width {
    GLTPrefs *prefs = [GLTPrefs sharedPrefs];
    BOOL selected = prefs.pill == pill;

    UIView *cell = [UIView new];
    cell.backgroundColor = prefs.backgroundColor ?: [UIColor colorWithWhite:0.12 alpha:0.9];
    cell.layer.cornerCurve = kCACornerCurveContinuous;
    cell.layer.cornerRadius = 17;
    if (selected) {
        cell.layer.borderWidth = 2;
        cell.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.9].CGColor;
    }

    GLTPillContent *content = [self contentForPill:pill];
    UILabel *label = [UILabel new];
    label.attributedText = [content attributedStringWithFont:font color:prefs.textColor];
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.6;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.textAlignment = NSTextAlignmentCenter;
    [label sizeToFit];

    CGFloat inner = width - 24;
    label.frame = CGRectMake(12, (44 - CGRectGetHeight(label.bounds)) / 2,
                             MIN(CGRectGetWidth(label.bounds), inner), CGRectGetHeight(label.bounds));
    if (CGRectGetWidth(label.bounds) > inner) {
        label.frame = CGRectMake(12, label.frame.origin.y, inner, CGRectGetHeight(label.bounds));
    }
    [cell addSubview:label];

    UILabel *name = [UILabel new];
    name.text = [GLTPrefs nameForPill:pill];
    name.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    name.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    name.textAlignment = NSTextAlignmentCenter;
    name.frame = CGRectMake(4, 46, width - 8, 14);
    [cell addSubview:name];

    cell.tag = pill;
    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pickerRowTapped:)];
    [cell addGestureRecognizer:tap];
    return cell;
}

- (void)showPicker {
    if (![self canPresentOverlay] || _pickerView) return;

    UIView *clock = [self visibleClock];
    if (!clock) return;

    UIImpactFeedbackGenerator *haptic =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];

    CGRect screen = [UIScreen mainScreen].bounds;
    UIView *host = _window.rootViewController.view;

    _pickerView = [[UIView alloc] initWithFrame:host.bounds];
    _pickerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [host addSubview:_pickerView];

    // Dim + blur behind the grid.
    UIControl *backdrop = [[UIControl alloc] initWithFrame:_pickerView.bounds];
    backdrop.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    [backdrop addTarget:self action:@selector(hidePicker) forControlEvents:UIControlEventTouchUpInside];
    [_pickerView addSubview:backdrop];

    UIVisualEffectView *blur =
        [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    blur.frame = _pickerView.bounds;
    blur.userInteractionEnabled = NO;
    [_pickerView addSubview:blur];

    GLTPickerList *list = [[GLTPickerList alloc] initWithFrame:CGRectZero];
    list.showsVerticalScrollIndicator = NO;
    list.clipsToBounds = NO;
    list.alwaysBounceVertical = YES;
    [_pickerView addSubview:list];

    UIFont *font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];

    CGFloat margin = 16;
    CGFloat spacing = 10;
    CGFloat columns = 3;
    CGFloat cellWidth = floor((screen.size.width - margin * 2 - spacing * (columns - 1)) / columns);
    CGFloat cellHeight = 66;

    NSArray *order = [GLTPrefs pillOrder];
    NSMutableArray<UIView *> *cells = [NSMutableArray array];

    for (NSUInteger i = 0; i < order.count; i++) {
        NSInteger pill = [order[i] integerValue];
        UIView *cell = [self pickerCellForPill:pill font:font width:cellWidth];

        NSUInteger column = i % (NSUInteger)columns;
        NSUInteger row = i / (NSUInteger)columns;
        cell.frame = CGRectMake(margin + column * (cellWidth + spacing),
                                22 + row * (cellHeight + spacing),
                                cellWidth, cellHeight);
        [list addSubview:cell];
        [cells addObject:cell];
    }

    NSUInteger rows = (order.count + (NSUInteger)columns - 1) / (NSUInteger)columns;
    CGFloat contentHeight = 22 + rows * (cellHeight + spacing);
    list.contentSize = CGSizeMake(screen.size.width, contentHeight);

    // Anchor the sheet under the pill.
    CGRect anchor = [self frameOfClock:clock];
    CGFloat top = CGRectGetMaxY(anchor) + 8;
    CGFloat available = screen.size.height - top - 40;
    list.frame = CGRectMake(0, top, screen.size.width, MIN(contentHeight, available));

    list.alpha = 0;
    for (UIView *cell in cells) {
        cell.alpha = 0;
        cell.transform = CGAffineTransformMakeScale(0.9, 0.9);
    }

    [UIView animateWithDuration:0.18 animations:^{
        list.alpha = 1;
    }];

    __block NSUInteger index = 0;
    for (UIView *cell in cells) {
        NSUInteger current = index++;
        [UIView animateWithDuration:0.42
                              delay:0.02 * current
             usingSpringWithDamping:0.72
              initialSpringVelocity:0.5
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            cell.alpha = 1;
            cell.transform = CGAffineTransformIdentity;
        } completion:nil];
    }

    [self layoutTouchView];
}

- (void)pickerRowTapped:(UITapGestureRecognizer *)gesture {
    NSInteger pill = gesture.view.tag;

    UISelectionFeedbackGenerator *haptic = [UISelectionFeedbackGenerator new];
    [haptic selectionChanged];

    [[GLTPrefs sharedPrefs] setPill:pill];

    if ([self wantsWeather]) {
        [[GLTWeather sharedWeather] refreshForcing:YES];
    }

    [self hidePicker];
    [self update];
}

- (void)hidePicker {
    UIView *picker = _pickerView;
    if (!picker) return;

    _pickerView = nil;
    picker.userInteractionEnabled = NO;

    [UIView animateWithDuration:0.16
                     animations:^{
        picker.alpha = 0;
        for (UIView *subview in picker.subviews) {
            if ([subview isKindOfClass:[GLTPickerList class]]) {
                for (UIView *cell in subview.subviews) {
                    cell.transform = CGAffineTransformMakeScale(0.94, 0.94);
                }
            } else if ([subview isKindOfClass:[UIVisualEffectView class]]) {
                ((UIVisualEffectView *)subview).effect = nil;
            }
        }
    } completion:^(BOOL finished) {
        [picker removeFromSuperview];
    }];

    [self layoutTouchView];
}

@end
