//
//  GLTEvents.m
//
//  Calendar and reminder snapshot. Only two days are ever needed: the "Next
//  Event" pill and the calendar card both stop at "tomorrow".
//
//  Recovered from 0x15cec…0x16350.
//

#import "Glint.h"

// How far ahead the tweak looks. The card copy says "today or tomorrow".
static const NSTimeInterval kGLTLookahead = 2 * 24 * 60 * 60;

@implementation GLTEvents

+ (GLTEvents *)sharedEvents {
    static GLTEvents *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [GLTEvents new]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    _store = [EKEventStore new];
    _upcomingEvents = @[];
    _reminders = @[];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(refresh)
                                                 name:EKEventStoreChangedNotification
                                               object:nil];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Authorisation

- (void)requestAccess {
    if (@available(iOS 17, *)) {
        [_store requestFullAccessToEventsWithCompletion:^(BOOL granted, NSError *error) {
            [self refresh];
        }];
        [_store requestFullAccessToRemindersWithCompletion:^(BOOL granted, NSError *error) {
            [self refresh];
        }];
    } else {
        [_store requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL granted, NSError *error) {
            [self refresh];
        }];
        [_store requestAccessToEntityType:EKEntityTypeReminder completion:^(BOOL granted, NSError *error) {
            [self refresh];
        }];
    }
}

- (BOOL)hasCalendarAccess {
    EKAuthorizationStatus status = [EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent];
    return status == EKAuthorizationStatusAuthorized || status == EKAuthorizationStatusFullAccess;
}

- (BOOL)hasRemindersAccess {
    EKAuthorizationStatus status = [EKEventStore authorizationStatusForEntityType:EKEntityTypeReminder];
    return status == EKAuthorizationStatusAuthorized || status == EKAuthorizationStatusFullAccess;
}

#pragma mark - Snapshot

- (void)refresh {
    NSDate *now = [NSDate date];
    NSDate *horizon = [now dateByAddingTimeInterval:kGLTLookahead];
    NSCalendar *calendar = [NSCalendar currentCalendar];

    if ([self hasCalendarAccess]) {
        NSDate *start = [calendar startOfDayForDate:now];
        NSPredicate *predicate = [_store predicateForEventsWithStartDate:start
                                                                endDate:horizon
                                                              calendars:nil];
        NSArray *events = [_store eventsMatchingPredicate:predicate];
        _upcomingEvents = [events sortedArrayUsingSelector:@selector(compareStartDateWithEvent:)];
    } else {
        _upcomingEvents = @[];
    }

    if ([self hasRemindersAccess]) {
        NSPredicate *predicate = [_store predicateForIncompleteRemindersWithDueDateStarting:now
                                                                                   ending:horizon
                                                                                calendars:nil];
        [_store fetchRemindersMatchingPredicate:predicate completion:^(NSArray *reminders) {
            NSArray *sorted = [reminders sortedArrayUsingComparator:^NSComparisonResult(EKReminder *a, EKReminder *b) {
                NSDate *left  = [a dueDateComponents].date ?: [NSDate distantFuture];
                NSDate *right = [b dueDateComponents].date ?: [NSDate distantFuture];
                return [left compare:right];
            }];
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_reminders = sorted ?: @[];
            });
        }];
    } else {
        _reminders = @[];
    }
}

- (void)completeReminder:(EKReminder *)reminder {
#if GLINT_VERIFICATION_BUILD
    return; // Read-only reminders during the first-device smoke test.
#endif
    if (GLTDeviceIsLocked()) return;
    reminder.completed = YES;
    [_store saveReminder:reminder commit:YES error:nil];
    [self refresh];
}

@end
