//
//  GLTInfoPlatters.m
//
//  The read-only cards: calendar, weather, storage, countdown, unlocks, the
//  accessory list, and the notification card. Each one is a thin layout over
//  data the controller already owns, so they are collected here.
//
//  Factories recovered from the anonymous sub-functions that follow each
//  class's .cxx_destruct: 0xf7f4 (events), 0x10ad8 (weather), 0x12600
//  (storage), 0x12e7c (countdown), 0x13340 (unlocks), 0xf19c (devices),
//  0x10640 (notification), 0xffd8 (reminders).
//

#import "Glint.h"
#import "GlintPrivate.h"

#pragma mark - Small builders

static UILabel *GLTLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

static UILabel *GLTCaption(NSString *text) {
    return GLTLabel(text, 13, UIFontWeightSemibold, [UIColor colorWithWhite:1 alpha:0.55]);
}

static GLTPlatterContent *GLTFill(NSArray<UIView *> *rows) {
    GLTPlatterContent *content = [GLTPlatterContent new];
    [content fillWith:rows];
    return content;
}

static UIStackView *GLTStack(NSArray<UIView *> *views, CGFloat spacing) {
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:views];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = spacing;
    return stack;
}

#pragma mark - Notification card

@implementation GLTNotificationPlatterView

- (void)open {
    [self.notification open];
    [self close];
}

@end

GLTPlatterContent *GLTMakeNotificationPlatter(GLTNotification *notification) {
    GLTNotificationPlatterView *content = [GLTNotificationPlatterView new];
    content.notification = notification;

    UIImageView *icon = [[UIImageView alloc] initWithImage:notification.icon];
    icon.layer.cornerRadius = 8;
    icon.layer.cornerCurve = kCACornerCurveContinuous;
    icon.clipsToBounds = YES;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [icon.widthAnchor constraintEqualToConstant:32],
        [icon.heightAnchor constraintEqualToConstant:32],
    ]];

    UILabel *app = GLTCaption([notification.appName uppercaseString]);
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[icon, app]];
    header.axis = UILayoutConstraintAxisHorizontal;
    header.spacing = 8;
    header.alignment = UIStackViewAlignmentCenter;

    UILabel *title = GLTLabel(notification.title, 15, UIFontWeightSemibold, [UIColor whiteColor]);
    title.numberOfLines = 1;

    NSMutableArray *rows = [NSMutableArray arrayWithObjects:header, title, nil];
    if (notification.message.length) {
        UILabel *message = GLTLabel(notification.message, 14, UIFontWeightRegular,
                                    [UIColor colorWithWhite:1 alpha:0.75]);
        [rows addObject:message];
    }

    [content fillWith:@[GLTStack(rows, 8)]];

    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:content action:@selector(open)];
    [content addGestureRecognizer:tap];
    content.userInteractionEnabled = YES;
    return content;
}

#pragma mark - Reminders card

@implementation GLTRemindersPlatterView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    GLTEvents *events = [GLTEvents sharedEvents];
    NSMutableArray *rows = [NSMutableArray arrayWithObject:GLTCaption(@"Reminders")];

    if (![events hasRemindersAccess]) {
        [rows addObject:GLTLabel(@"Glint can't read your reminders.", 15, UIFontWeightRegular,
                                 [UIColor colorWithWhite:1 alpha:0.75])];
    } else if (events.reminders.count == 0) {
        [rows addObject:GLTLabel(@"All done.", 15, UIFontWeightRegular,
                                 [UIColor colorWithWhite:1 alpha:0.75])];
    } else {
        _shown = [events.reminders subarrayWithRange:
                  NSMakeRange(0, MIN((NSUInteger)6, events.reminders.count))];

        NSUInteger index = 0;
        for (EKReminder *reminder in _shown) {
            UIButton *check = [UIButton buttonWithType:UIButtonTypeSystem];
            UIImage *image = [UIImage systemImageNamed:@"circle"
                                     withConfiguration:[UIImageSymbolConfiguration
                                                          configurationWithPointSize:20]];
            [check setImage:image forState:UIControlStateNormal];
            check.tintColor = [UIColor colorWithCGColor:reminder.calendar.CGColor];
            check.tag = (NSInteger)index++;
            [check addTarget:self action:@selector(complete:) forControlEvents:UIControlEventTouchUpInside];
            [check setContentHuggingPriority:UILayoutPriorityRequired
                                     forAxis:UILayoutConstraintAxisHorizontal];

            UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:
                                @[check, GLTLabel(reminder.title ?: @"", 15,
                                                  UIFontWeightRegular, [UIColor whiteColor])]];
            row.axis = UILayoutConstraintAxisHorizontal;
            row.spacing = 10;
            row.alignment = UIStackViewAlignmentCenter;
            [rows addObject:row];
        }
    }

    [self fillWith:@[GLTStack(rows, 10)]];
    return self;
}

- (void)complete:(UIButton *)button {
    if (button.tag < 0 || button.tag >= (NSInteger)_shown.count) return;

    EKReminder *reminder = _shown[(NSUInteger)button.tag];
    [button setImage:[UIImage systemImageNamed:@"checkmark.circle.fill"
                             withConfiguration:[UIImageSymbolConfiguration
                                                  configurationWithPointSize:20]]
            forState:UIControlStateNormal];
    button.enabled = NO;

    [[GLTEvents sharedEvents] completeReminder:reminder];
}

@end

GLTPlatterContent *GLTMakeRemindersPlatter(void) {
    return [[GLTRemindersPlatterView alloc] initWithFrame:CGRectZero];
}

#pragma mark - Events card

GLTPlatterContent *GLTMakeEventsPlatter(void) {
    GLTEvents *events = [GLTEvents sharedEvents];
    NSMutableArray *rows = [NSMutableArray arrayWithObject:GLTCaption(@"Upcoming")];

    if (![events hasCalendarAccess]) {
        [rows addObject:GLTLabel(@"Glint can't read your calendar.", 15, UIFontWeightRegular,
                                 [UIColor colorWithWhite:1 alpha:0.75])];
        return GLTFill(@[GLTStack(rows, 10)]);
    }

    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateFormatter *timeFormatter = [NSDateFormatter new];
    timeFormatter.dateStyle = NSDateFormatterNoStyle;
    timeFormatter.timeStyle = NSDateFormatterShortStyle;
    timeFormatter.doesRelativeDateFormatting = YES;

    NSMutableArray<EKEvent *> *shown = [NSMutableArray array];
    for (EKEvent *event in events.upcomingEvents) {
        if ([event.endDate timeIntervalSinceNow] <= 0) continue;
        [shown addObject:event];
        if (shown.count >= 5) break;
    }

    if (shown.count == 0) {
        [rows addObject:GLTLabel(@"No more events today or tomorrow.", 15, UIFontWeightRegular,
                                 [UIColor colorWithWhite:1 alpha:0.75])];
        return GLTFill(@[GLTStack(rows, 10)]);
    }

    NSDateFormatter *dayFormatter = [NSDateFormatter new];
    dayFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"EEE"
                                                              options:0
                                                               locale:[NSLocale currentLocale]];

    for (EKEvent *event in shown) {
        UIView *dot = [UIView new];
        dot.backgroundColor = [UIColor colorWithCGColor:event.calendar.CGColor];
        dot.layer.cornerRadius = 2;
        dot.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [dot.widthAnchor constraintEqualToConstant:4],
            [dot.heightAnchor constraintEqualToConstant:28],
        ]];

        UILabel *title = GLTLabel(event.title ?: @"Event", 15, UIFontWeightMedium, [UIColor whiteColor]);
        title.numberOfLines = 1;

        NSString *when;
        if (event.isAllDay) {
            when = [NSString stringWithFormat:@"All day · %@", [dayFormatter stringFromDate:event.startDate]];
        } else if ([calendar isDateInTomorrow:event.startDate]) {
            when = [NSString stringWithFormat:@"Tomorrow, %@",
                    [timeFormatter stringFromDate:event.startDate]];
        } else {
            when = [timeFormatter stringFromDate:event.startDate];
        }
        UILabel *subtitle = GLTLabel(when, 12, UIFontWeightRegular,
                                     [UIColor colorWithWhite:1 alpha:0.55]);

        UIStackView *text = GLTStack(@[title, subtitle], 2);
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[dot, text]];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.spacing = 10;
        row.alignment = UIStackViewAlignmentTop;
        [rows addObject:row];
    }

    return GLTFill(@[GLTStack(rows, 10)]);
}

#pragma mark - Weather card

GLTPlatterContent *GLTMakeWeatherPlatter(void) {
    GLTWeather *weather = [GLTWeather sharedWeather];
    NSMutableArray *rows = [NSMutableArray array];

    NSString *place = weather.place.length ? weather.place : @"Current Location";
    [rows addObject:GLTCaption([place uppercaseString])];

    if (!weather.hasData) {
        NSString *problem = weather.problem.length ? weather.problem
                                                  : @"The weather isn't available right now.";
        [rows addObject:GLTLabel(problem, 15, UIFontWeightRegular,
                                 [UIColor colorWithWhite:1 alpha:0.75])];
        return GLTFill(@[GLTStack(rows, 10)]);
    }

    UIImageView *glyph = [[UIImageView alloc] initWithImage:
                          GLTSymbol([GLTWeather symbolForCode:weather.code isDay:weather.isDay],
                                    30, UIFontWeightRegular)];
    glyph.tintColor = [UIColor whiteColor];
    glyph.contentMode = UIViewContentModeScaleAspectFit;

    UILabel *temperature = GLTLabel([GLTWeather temperatureString:weather.temperature],
                                    30, UIFontWeightLight, [UIColor whiteColor]);
    UIStackView *headline = [[UIStackView alloc] initWithArrangedSubviews:@[glyph, temperature]];
    headline.axis = UILayoutConstraintAxisHorizontal;
    headline.spacing = 8;
    headline.alignment = UIStackViewAlignmentCenter;
    [rows addObject:headline];

    [rows addObject:GLTLabel([GLTWeather descriptionForCode:weather.code],
                             15, UIFontWeightMedium, [UIColor colorWithWhite:1 alpha:0.85])];
    [rows addObject:GLTLabel([NSString stringWithFormat:@"H %@  L %@",
                              [GLTWeather temperatureString:weather.high],
                              [GLTWeather temperatureString:weather.low]],
                             14, UIFontWeightRegular, [UIColor colorWithWhite:1 alpha:0.6])];

    if (weather.rainChance > 0) {
        [rows addObject:GLTLabel([NSString stringWithFormat:@"%ld%% chance of rain",
                                  (long)weather.rainChance],
                                 13, UIFontWeightRegular, [UIColor colorWithWhite:1 alpha:0.55])];
    }

    // Hourly strip.
    NSMutableArray<UIView *> *hours = [NSMutableArray array];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"j"
                                                           options:0
                                                            locale:[NSLocale currentLocale]];

    for (GLTWeatherHour *hour in weather.hours) {
        UILabel *time = GLTLabel([formatter stringFromDate:hour.date], 11, UIFontWeightMedium,
                                 [UIColor colorWithWhite:1 alpha:0.55]);
        time.textAlignment = NSTextAlignmentCenter;

        UIImageView *icon = [[UIImageView alloc] initWithImage:
                             GLTSymbol([GLTWeather symbolForCode:hour.code isDay:hour.isDay],
                                       15, UIFontWeightRegular)];
        icon.tintColor = [UIColor whiteColor];
        icon.contentMode = UIViewContentModeScaleAspectFit;

        UILabel *value = GLTLabel([GLTWeather temperatureString:hour.temperature], 12,
                                  UIFontWeightSemibold, [UIColor whiteColor]);
        value.textAlignment = NSTextAlignmentCenter;

        UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[time, icon, value]];
        column.axis = UILayoutConstraintAxisVertical;
        column.spacing = 4;
        column.alignment = UIStackViewAlignmentCenter;
        [hours addObject:column];
        if (hours.count >= 10) break;
    }

    if (hours.count) {
        UIStackView *strip = [[UIStackView alloc] initWithArrangedSubviews:hours];
        strip.axis = UILayoutConstraintAxisHorizontal;
        strip.distribution = UIStackViewDistributionEqualSpacing;
        [rows addObject:strip];
    }

    [rows addObject:GLTLabel(@"Weather data by Open-Meteo.com", 10, UIFontWeightRegular,
                             [UIColor colorWithWhite:1 alpha:0.35])];

    return GLTFill(@[GLTStack(rows, 10)]);
}

#pragma mark - Storage card

GLTPlatterContent *GLTMakeStoragePlatter(void) {
    NSDictionary *attributes =
        [[NSFileManager defaultManager] attributesOfFileSystemForPath:@"/private/var" error:nil];
    long long free  = [attributes[NSFileSystemFreeSize] longLongValue];
    long long total = [attributes[NSFileSystemSize] longLongValue];

    NSByteCountFormatter *formatter = [NSByteCountFormatter new];
    formatter.countStyle = NSByteCountFormatterCountStyleFile;

    NSMutableArray *rows = [NSMutableArray arrayWithObject:GLTCaption(@"Storage")];
    [rows addObject:GLTLabel([NSString stringWithFormat:@"%@ free of %@",
                              [formatter stringFromByteCount:free],
                              [formatter stringFromByteCount:total]],
                             15, UIFontWeightRegular, [UIColor whiteColor])];

    NSArray *memory = @[GLTCaption(@"Memory")];
    [rows addObjectsFromArray:memory];

    NSProcessInfo *process = [NSProcessInfo processInfo];
    unsigned long long physical = process.physicalMemory;
    [rows addObject:GLTLabel([NSString stringWithFormat:@"%@ RAM",
                              [formatter stringFromByteCount:(long long)physical]],
                             13, UIFontWeightRegular, [UIColor colorWithWhite:1 alpha:0.6])];

    return GLTFill(@[GLTStack(rows, 10)]);
}

#pragma mark - Countdown card

GLTPlatterContent *GLTMakeCountdownPlatter(void) {
    GLTPrefs *prefs = [GLTPrefs sharedPrefs];
    NSMutableArray *rows = [NSMutableArray arrayWithObject:GLTCaption(@"Countdown")];

    if (!prefs.countdownDate) {
        [rows addObject:GLTLabel(@"Set a date in Glint's settings.", 15, UIFontWeightRegular,
                                 [UIColor colorWithWhite:1 alpha:0.75])];
        return GLTFill(@[GLTStack(rows, 10)]);
    }

    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate *from = [calendar startOfDayForDate:[NSDate date]];
    NSDate *to = [calendar startOfDayForDate:prefs.countdownDate];
    NSInteger days = [[calendar components:NSCalendarUnitDay fromDate:from toDate:to options:0] day];

    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateStyle = NSDateFormatterLongStyle;
    formatter.timeStyle = NSDateFormatterNoStyle;

    NSString *title = prefs.countdownTitle.length ? prefs.countdownTitle : @"the date";
    NSString *target = [formatter stringFromDate:prefs.countdownDate];

    if (days == 0) {
        [rows addObject:GLTLabel([NSString stringWithFormat:@"%@ is today", title], 17,
                                 UIFontWeightSemibold, [UIColor whiteColor])];
    } else if (days > 0) {
        [rows addObject:GLTLabel([NSString stringWithFormat:@"%ld", (long)days], 34,
                                 UIFontWeightLight, [UIColor whiteColor])];
        [rows addObject:GLTLabel([NSString stringWithFormat:@"%@ until %@",
                                  days == 1 ? @"day" : @"days", target],
                                 14, UIFontWeightRegular, [UIColor colorWithWhite:1 alpha:0.7])];
    } else {
        [rows addObject:GLTLabel([NSString stringWithFormat:@"%@ since %@", title, target],
                                 15, UIFontWeightRegular, [UIColor colorWithWhite:1 alpha:0.7])];
    }

    return GLTFill(@[GLTStack(rows, 6)]);
}

#pragma mark - Unlocks card

GLTPlatterContent *GLTMakeUnlocksPlatter(void) {
    GLTUnlocks *unlocks = [GLTUnlocks sharedUnlocks];
    NSMutableArray *rows = [NSMutableArray arrayWithObject:GLTCaption(@"Unlocks")];

    [rows addObject:GLTLabel([NSString stringWithFormat:@"%ld", (long)unlocks.today], 34,
                             UIFontWeightLight, [UIColor whiteColor])];
    [rows addObject:GLTLabel(unlocks.today == 1 ? @"unlock today" : @"unlocks today", 14,
                             UIFontWeightRegular, [UIColor colorWithWhite:1 alpha:0.7])];
    [rows addObject:GLTLabel([NSString stringWithFormat:@"Yesterday: %ld", (long)unlocks.yesterday],
                             12, UIFontWeightRegular, [UIColor colorWithWhite:1 alpha:0.45])];

    return GLTFill(@[GLTStack(rows, 6)]);
}

#pragma mark - Device card

GLTPlatterContent *GLTMakeDevicePlatter(GLTPillContent *summary) {
    NSMutableArray *rows = [NSMutableArray arrayWithObject:GLTCaption(@"Devices")];

    for (GLTDevice *device in GLTConnectedDevices()) {
        UIImageView *icon = [[UIImageView alloc] initWithImage:
                             device.glyph ?: GLTSymbol(@"headphones", 15, UIFontWeightRegular)];
        icon.tintColor = [UIColor whiteColor];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [icon.widthAnchor constraintEqualToConstant:22],
            [icon.heightAnchor constraintEqualToConstant:22],
        ]];

        UILabel *percent = GLTLabel(GLTPercentText(device.percent), 15, UIFontWeightSemibold,
                                    device.charging ? [UIColor systemGreenColor] : [UIColor whiteColor]);
        percent.textAlignment = NSTextAlignmentRight;

        UILabel *name = GLTLabel(device.name ?: @"", 15, UIFontWeightMedium, [UIColor whiteColor]);
        name.numberOfLines = 1;

        UIStackView *left = [[UIStackView alloc] initWithArrangedSubviews:@[icon, name]];
        left.axis = UILayoutConstraintAxisHorizontal;
        left.spacing = 8;
        left.alignment = UIStackViewAlignmentCenter;

        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[left, percent]];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.distribution = UIStackViewDistributionEqualSpacing;
        row.alignment = UIStackViewAlignmentCenter;
        [rows addObject:row];

        if (device.details.length) {
            [rows addObject:GLTLabel(device.details, 11, UIFontWeightRegular,
                                     [UIColor colorWithWhite:1 alpha:0.45])];
        }
    }

    return GLTFill(@[GLTStack(rows, 8)]);
}
