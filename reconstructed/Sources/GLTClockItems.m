//
//  GLTClockItems.m
//
//  Alarm and timer snapshot, read from MobileTimer. The framework is private,
//  so it is dlopen'd and its classes declared locally.
//
//  Recovered from 0x17654…0x17f6c.
//

#import "Glint.h"
#import <dlfcn.h>

#pragma mark - MobileTimer surface

@interface MTAlarm : NSObject
@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property (nonatomic, readonly) NSDate *nextFireDate;
@property (nonatomic, readonly) NSString *displayTitle;
@end

@interface MTAlarmManager : NSObject
- (NSArray *)alarmsSync;
@end

typedef NS_ENUM(NSInteger, MTTimerState) {
    MTTimerStateStopped = 1,
    MTTimerStatePaused  = 2,
    MTTimerStateRunning = 3,
};

@interface MTTimer : NSObject
@property (nonatomic, readonly) NSDate *fireDate;
@property (nonatomic, readonly) double remainingTime;
@property (nonatomic, readonly) double duration;
@property (nonatomic, readonly) MTTimerState state;
@end

@interface MTTimerManager : NSObject
- (NSArray *)timersSync;
- (MTTimer *)getCurrentTimerSync;
@end

#pragma mark -

@implementation GLTClockItems

+ (GLTClockItems *)sharedItems {
    static GLTClockItems *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [GLTClockItems new]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    dlopen("/System/Library/PrivateFrameworks/MobileTimer.framework/MobileTimer", RTLD_LAZY);

    Class alarmClass = NSClassFromString(@"MTAlarmManager");
    Class timerClass = NSClassFromString(@"MTTimerManager");
    // Original 0x17698..0x176c4 owns new manager instances, not singletons.
    _alarmManager = [alarmClass new];
    _timerManager = [timerClass new];

    // MobileTimer's synchronous accessors block on its own queue, so keep them
    // off the main thread.
    _queue = dispatch_queue_create("com.antonym.glint.clock", DISPATCH_QUEUE_SERIAL);
    _alarms = @[];

    [self refresh];
    return self;
}

#pragma mark - Snapshot

- (void)refresh {
    if (_refreshing) return;
    _refreshing = YES;

    dispatch_async(_queue, ^{
        NSMutableArray<GLTAlarm *> *alarms = [NSMutableArray array];

        NSArray *rawAlarms = [self->_alarmManager respondsToSelector:@selector(alarmsSync)]
            ? [self->_alarmManager alarmsSync] : nil;
        for (MTAlarm *alarm in rawAlarms) {
            if (![alarm respondsToSelector:@selector(isEnabled)] || ![alarm isEnabled]) continue;
            if (![alarm respondsToSelector:@selector(nextFireDate)]) continue;

            NSDate *fireDate = [alarm nextFireDate];
            if (!fireDate || [fireDate timeIntervalSinceNow] <= 0) continue;

            GLTAlarm *entry = [GLTAlarm new];
            entry.title = [alarm respondsToSelector:@selector(displayTitle)] ? [alarm displayTitle] : nil;
            entry.fireDate = fireDate;
            [alarms addObject:entry];
        }

        [alarms sortUsingComparator:^NSComparisonResult(GLTAlarm *a, GLTAlarm *b) {
            return [a.fireDate compare:b.fireDate];
        }];

        NSDate *fireDate = nil;
        double remaining = 0;
        double duration = 0;

        // Original 0x17a14..0x17ce4 considers both APIs, chooses the earliest
        // running timer, then falls back to the first positive paused timer.
        NSMutableArray<MTTimer *> *timers = [NSMutableArray array];
        if ([self->_timerManager respondsToSelector:@selector(timersSync)]) {
            [timers addObjectsFromArray:[self->_timerManager timersSync] ?: @[]];
        }
        if ([self->_timerManager respondsToSelector:@selector(getCurrentTimerSync)]) {
            MTTimer *current = [self->_timerManager getCurrentTimerSync];
            if (current) [timers addObject:current];
        }
        MTTimer *runningTimer = nil;
        MTTimer *pausedTimer = nil;
        for (MTTimer *timer in timers) {
            if (![timer respondsToSelector:@selector(state)]) continue;
            MTTimerState state = timer.state;
            if (state == MTTimerStateRunning && [timer respondsToSelector:@selector(fireDate)]) {
                NSDate *candidateFireDate = timer.fireDate;
                if (candidateFireDate && [candidateFireDate timeIntervalSinceNow] > 0 &&
                    (!runningTimer || [candidateFireDate compare:runningTimer.fireDate] == NSOrderedAscending)) {
                    runningTimer = timer;
                }
            } else if (state == MTTimerStatePaused && [timer respondsToSelector:@selector(remainingTime)] &&
                       timer.remainingTime > 0 && !pausedTimer) {
                pausedTimer = timer;
            }
        }
        fireDate = runningTimer.fireDate;
        remaining = runningTimer ? 0 : pausedTimer.remainingTime;
        MTTimer *selectedTimer = runningTimer ?: pausedTimer;
        duration = [selectedTimer respondsToSelector:@selector(duration)] ? selectedTimer.duration : 0;

        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL changed = !((self->_alarms == nil && alarms.count == 0)
                             || [self->_alarms isEqualToArray:alarms]);
            BOOL timerChanged = !((self->_timerFireDate == nil && fireDate == nil)
                                  || [self->_timerFireDate isEqualToDate:fireDate])
                                || self->_pausedTimerRemaining != remaining;

            self->_alarms = alarms;
            self->_timerFireDate = fireDate;
            self->_pausedTimerRemaining = remaining;
            self->_timerDuration = duration;
            self->_refreshing = NO;

            if (changed || timerChanged) {
                [[NSNotificationCenter defaultCenter] postNotificationName:GLTSourcesDidChangeNotification
                                                                    object:nil];
            }
        });
    });
}

#pragma mark - Accessors

- (NSArray<GLTAlarm *> *)alarms {
    return _alarms;
}

- (NSDate *)timerFireDate {
    return _timerFireDate;
}

- (double)pausedTimerRemaining {
    return _pausedTimerRemaining;
}

- (double)timerDuration {
    return _timerDuration;
}

@end
