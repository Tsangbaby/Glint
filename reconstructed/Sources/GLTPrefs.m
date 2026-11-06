//
//  GLTPrefs.m
//
//  Mirrors -[GLTPrefs reload] at 0x1b958. Every key, default and clamp below
//  was read out of that function; the preference bundle's Root.plist must stay
//  in sync with it.
//

#import "Glint.h"

@interface GLTPrefs ()
@property (nonatomic, readwrite) BOOL enabled;
@property (nonatomic, readwrite) BOOL tapToCycle;
@property (nonatomic, readwrite) BOOL showSeconds;
@property (nonatomic, readwrite) BOOL showMediaWhilePlaying;
@property (nonatomic, readwrite) BOOL replaceBanners;
@property (nonatomic, readwrite) BOOL deviceConnections;
@property (nonatomic, readwrite) BOOL replaceVolumeHUD;
@property (nonatomic, readwrite) UIColor *backgroundColor;
@property (nonatomic, readwrite) UIColor *textColor;
@property (nonatomic, readwrite) double notificationDuration;
@property (nonatomic, readwrite) NSString *weatherCity;
@property (nonatomic, readwrite) NSString *countdownTitle;
@property (nonatomic, readwrite) NSDate *countdownDate;
@property (nonatomic, readwrite) double volumeDuration;
@end

@implementation GLTPrefs

@synthesize pill = _pill;

#pragma mark - Singleton

static void GLTPrefsReloadCallback(CFNotificationCenterRef center,
                                   void *observer,
                                   CFStringRef name,
                                   const void *object,
                                   CFDictionaryRef userInfo)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[GLTPrefs sharedPrefs] reload];
        [[NSNotificationCenter defaultCenter] postNotificationName:GLTPrefsDidChangeNotification
                                                            object:nil];
    });
}

+ (GLTPrefs *)sharedPrefs {
    static GLTPrefs *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [GLTPrefs new];
        [shared reload];

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)shared,
                                        GLTPrefsReloadCallback,
                                        (__bridge CFStringRef)kGLTReloadNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    });
    return shared;
}

#pragma mark - Raw defaults access

- (id)objectForKey:(NSString *)key {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)kGLTPrefsDomain);
    return CFBridgingRelease(value);
}

- (BOOL)boolForKey:(NSString *)key fallback:(BOOL)fallback {
    id value = [self objectForKey:key];
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue];
    }
    return fallback;
}

- (double)doubleForKey:(NSString *)key fallback:(double)fallback min:(double)min max:(double)max {
    id value = [self objectForKey:key];
    double result = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
    if (result < min) result = min;
    if (result > max) result = max;
    return result;
}

#pragma mark - Pill catalogue

// Order used by the picker and by "Tap to Cycle". Recovered from the
// NSConstantArray returned by +pillOrder (0x2f1d8), which holds 0…14.
+ (NSArray *)pillOrder {
    return @[@(GLTPillTime), @(GLTPillDate), @(GLTPillBattery), @(GLTPillNetwork),
             @(GLTPillNowPlaying), @(GLTPillCalendar), @(GLTPillReminders),
             @(GLTPillWeather), @(GLTPillAlarm), @(GLTPillNextEvent), @(GLTPillSun),
             @(GLTPillStorage), @(GLTPillCountdown), @(GLTPillUnlocks),
             @(GLTPillQuickMessage)];
}

// Backed by the __const tables at 0x2c7a0 (names) and 0x2c818 (symbols).
+ (NSString *)nameForPill:(NSInteger)pill {
    static NSArray *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @[@"Time", @"Date", @"Battery", @"Network Speed", @"Now Playing",
                  @"Calendar", @"Reminders", @"Weather", @"Alarm & Timer",
                  @"Next Event", @"Sunrise & Sunset", @"Storage & Memory",
                  @"Countdown", @"Unlocks", @"Quick Message"];
    });
    if (pill < 0 || pill >= (NSInteger)names.count) return nil;
    return names[pill];
}

+ (NSString *)symbolForPill:(NSInteger)pill {
    static NSArray *symbols;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        symbols = @[@"clock", @"calendar", @"battery.100", @"arrow.up.arrow.down",
                    @"music.note", @"calendar.badge.clock", @"checklist", @"cloud.sun",
                    @"alarm", @"calendar.badge.clock", @"sunrise", @"internaldrive",
                    @"hourglass", @"lock.open", @"square.and.pencil"];
    });
    if (pill < 0 || pill >= (NSInteger)symbols.count) return nil;
    return symbols[pill];
}

- (void)setPill:(long long)pill {
    _pill = pill;
    CFPreferencesSetAppValue(CFSTR("pill"), (__bridge CFPropertyListRef)@(pill),
                             (__bridge CFStringRef)kGLTPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kGLTPrefsDomain);
}

#pragma mark - Colour parsing

// "#RRGGBB" -> UIColor, or nil when the string is not a colour literal.
static UIColor *GLTColorFromString(NSString *string) {
    if (![string isKindOfClass:[NSString class]]) return nil;

    NSString *trimmed = [string stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (trimmed.length != 6) return nil;

    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    if (![scanner scanHexInt:&rgb]) return nil;

    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

#pragma mark - Reload

- (void)reload {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kGLTPrefsDomain);

    _enabled              = [self boolForKey:@"enabled" fallback:NO];
    _tapToCycle           = [self boolForKey:@"tapToCycle" fallback:YES];
    _showSeconds          = [self boolForKey:@"showSeconds" fallback:NO];
    _showMediaWhilePlaying = [self boolForKey:@"showMediaWhilePlaying" fallback:NO];
    _replaceBanners       = [self boolForKey:@"replaceBanners" fallback:NO];
    _deviceConnections    = [self boolForKey:@"deviceConnections" fallback:NO];
    _replaceVolumeHUD     = [self boolForKey:@"replaceVolumeHUD" fallback:NO];

    _notificationDuration = [self doubleForKey:@"notificationDuration" fallback:3 min:1 max:8];
    _volumeDuration       = [self doubleForKey:@"volumeDuration" fallback:1.5 min:0.5 max:5];

    // backgroundStyle 0 = Default (translucent dark), 1 = Color (user pick)
    double style = [self doubleForKey:@"backgroundStyle" fallback:0 min:0 max:1];
    if (style == 1) {
        _backgroundColor = GLTColorFromString([self objectForKey:@"backgroundColor"]) ?: [UIColor blackColor];
    } else {
        _backgroundColor = nil;
    }

    _textColor = GLTColorFromString([self objectForKey:@"textColor"]) ?: [UIColor whiteColor];

    id city = [self objectForKey:@"weatherCity"];
    if ([city isKindOfClass:[NSString class]]) {
        NSString *trimmed = [city stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        _weatherCity = trimmed.length ? trimmed : nil;
    } else {
        _weatherCity = nil;
    }

    id title = [self objectForKey:@"countdownTitle"];
    if ([title isKindOfClass:[NSString class]]) {
        NSString *trimmed = [title stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        _countdownTitle = trimmed.length ? trimmed : nil;
    } else {
        _countdownTitle = nil;
    }

    id date = [self objectForKey:@"countdownDate"];
    _countdownDate = [date isKindOfClass:[NSDate class]] ? date : nil;

    _pill = (long long)[self doubleForKey:@"pill" fallback:0 min:0 max:14];
}

@end
