// Functional reconstruction from the supplied ObjC metadata/fingerprints.
// Multi-day rollover is an explicit conservative policy, not proven binary parity.
#import "GLTUnlocks.h"
#import "GLTRuntime.h"
#import <notify.h>
#import <limits.h>

static CFStringRef const GLTUnlockDomain = CFSTR("com.antonym.glint.unlocks");

static NSString *GLTUnlockDay(NSDate *date) {
    NSDateComponents *parts = [[NSCalendar currentCalendar]
        components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:date];
    return [NSString stringWithFormat:@"%04ld-%02ld-%02ld", (long)parts.year, (long)parts.month, (long)parts.day];
}

@implementation GLTUnlocks

+ (GLTUnlocks *)sharedUnlocks {
    static GLTUnlocks *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [GLTUnlocks new]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _lockToken = -1;
    _locked = YES;
    CFPreferencesAppSynchronize(GLTUnlockDomain);
    id day = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("day"), GLTUnlockDomain));
    id today = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("today"), GLTUnlockDomain));
    id yesterday = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("yesterday"), GLTUnlockDomain));
    _day = [day isKindOfClass:[NSString class]] ? [day copy] : nil;
    _today = [today respondsToSelector:@selector(integerValue)] ? MAX(0, [today integerValue]) : 0;
    _yesterday = [yesterday respondsToSelector:@selector(integerValue)] ? MAX(0, [yesterday integerValue]) : 0;
    [self rollOverIfNeeded];

    __weak typeof(self) weakSelf = self;
    int status = notify_register_dispatch("com.apple.springboard.lockstate", &_lockToken,
                                         dispatch_get_main_queue(), ^(int token) {
        GLTUnlocks *strongSelf = weakSelf;
        if (!strongSelf) return;
        uint64_t state = 1;
        if (notify_get_state(token, &state) == NOTIFY_STATUS_OK) {
            [strongSelf lockStateChanged:state != 0];
        } else {
            strongSelf->_hasLockState = NO;
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:GLTLockStateDidChangeNotification object:nil];
    });
    if (status == NOTIFY_STATUS_OK) {
        uint64_t state = 1;
        if (notify_get_state(_lockToken, &state) == NOTIFY_STATUS_OK) {
            _locked = state != 0;
            _hasLockState = YES;
        }
    } else {
        _lockToken = -1;
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dayChanged:)
                                                 name:NSCalendarDayChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dayChanged:)
                                                 name:NSSystemTimeZoneDidChangeNotification object:nil];
    return self;
}

- (void)dealloc {
    if (_lockToken >= 0) notify_cancel(_lockToken);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)dayChanged:(NSNotification *)notification {
    (void)notification;
    [self rollOverIfNeeded];
}

- (void)rollOverIfNeeded {
    NSDate *now = [NSDate date];
    NSString *today = GLTUnlockDay(now);
    if ([_day isEqualToString:today]) return;
    NSDate *previous = [[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitDay
                                                               value:-1 toDate:now options:0];
    _yesterday = [_day isEqualToString:GLTUnlockDay(previous)] ? _today : 0;
    _today = 0;
    _day = [today copy];
    [self save];
}

- (void)lockStateChanged:(BOOL)locked {
    if (![NSThread isMainThread]) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf lockStateChanged:locked]; });
        return;
    }
    [self rollOverIfNeeded];
    BOOL unlocked = _hasLockState && _locked && !locked;
    _locked = locked;
    _hasLockState = YES;
    if (unlocked && _today < LLONG_MAX) {
        _today++;
        [self save];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"GLTSourcesDidChangeNotification" object:nil];
        });
    }
}

- (long long)today {
    [self rollOverIfNeeded];
    return _today;
}

- (long long)yesterday {
    [self rollOverIfNeeded];
    return _yesterday;
}

- (void)save {
    CFPreferencesSetAppValue(CFSTR("day"), (__bridge CFPropertyListRef)_day, GLTUnlockDomain);
    CFPreferencesSetAppValue(CFSTR("today"), (__bridge CFPropertyListRef)@((NSInteger)_today), GLTUnlockDomain);
    CFPreferencesSetAppValue(CFSTR("yesterday"), (__bridge CFPropertyListRef)@((NSInteger)_yesterday), GLTUnlockDomain);
    CFPreferencesAppSynchronize(GLTUnlockDomain);
}

@end
