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
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <mach/vm_statistics.h>

#pragma mark - Small builders

static UILabel *GLTLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

static UILabel *GLTCaption(NSString *text) {
    return GLTLabel([text uppercaseString], 13, UIFontWeightSemibold, [UIColor colorWithWhite:1 alpha:0.6]);
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
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    return stack;
}

static UILabel *GLTInfoMessage(NSString *text) {
    UILabel *label = GLTLabel(text, 15, UIFontWeightRegular, [UIColor colorWithWhite:1 alpha:0.6]);
    label.numberOfLines = 0;
    return label;
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
        [icon.widthAnchor constraintEqualToConstant:36],
        [icon.heightAnchor constraintEqualToConstant:36],
    ]];
    UILabel *app = GLTCaption(notification.appName);
    UILabel *title = GLTLabel(notification.title, 16, UIFontWeightSemibold, [UIColor whiteColor]);
    title.hidden = notification.title.length == 0;
    UILabel *message = GLTLabel(notification.message ?: @"", 15, UIFontWeightRegular, [UIColor whiteColor]);
    message.numberOfLines = 4;
    UIStackView *text = GLTStack(@[app, title, message], 3);
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[icon, text]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 12;
    row.alignment = UIStackViewAlignmentTop;
    [content fillWith:@[row]];
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
        [rows addObject:GLTInfoMessage(@"Glint can't read your reminders.")];
    } else if (events.reminders.count == 0) {
        [rows addObject:GLTInfoMessage(@"All done.")];
    } else {
        _shown = [events.reminders subarrayWithRange:
                  NSMakeRange(0, MIN((NSUInteger)5, events.reminders.count))];

        NSUInteger index = 0;
        for (EKReminder *reminder in _shown) {
            UIButton *check = [UIButton buttonWithType:UIButtonTypeSystem];
            UIImage *image = [UIImage systemImageNamed:@"circle"
                                     withConfiguration:[UIImageSymbolConfiguration
                                                          configurationWithPointSize:20 weight:UIImageSymbolWeightRegular]];
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

    [self fillWith:@[GLTStack(rows, 12)]];
    return self;
}

- (void)complete:(UIButton *)button {
    if (button.tag < 0 || button.tag >= (NSInteger)_shown.count) return;

    EKReminder *reminder = _shown[(NSUInteger)button.tag];
    [button setImage:[UIImage systemImageNamed:@"checkmark.circle.fill"
                             withConfiguration:[UIImageSymbolConfiguration
                                                  configurationWithPointSize:20 weight:UIImageSymbolWeightRegular]]
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
        [rows addObject:GLTInfoMessage(@"Glint can't read your calendar.")];
        return GLTFill(@[GLTStack(rows, 12)]);
    }
    NSArray<EKEvent *> *shown = [events.upcomingEvents subarrayWithRange:
                                NSMakeRange(0, MIN((NSUInteger)4, events.upcomingEvents.count))];
    if (shown.count == 0) {
        [rows addObject:GLTInfoMessage(@"No more events today or tomorrow.")];
        return GLTFill(@[GLTStack(rows, 12)]);
    }
    NSDateFormatter *timeFormatter = [NSDateFormatter new];
    timeFormatter.dateStyle = NSDateFormatterNoStyle;
    timeFormatter.timeStyle = NSDateFormatterShortStyle;
    timeFormatter.doesRelativeDateFormatting = YES;
    NSCalendar *calendar = [NSCalendar currentCalendar];
    for (EKEvent *event in shown) {
        UIView *dot = [UIView new];
        dot.backgroundColor = [UIColor colorWithCGColor:event.calendar.CGColor];
        dot.layer.cornerRadius = 2;
        dot.translatesAutoresizingMaskIntoConstraints = NO;
        [dot.widthAnchor constraintEqualToConstant:4].active = YES;
        UILabel *title = GLTLabel(event.title ?: @"", 15, UIFontWeightSemibold, [UIColor whiteColor]);
        title.numberOfLines = 1;
        NSString *when;
        if (event.isAllDay) {
            when = @"All day";
        } else {
            when = [NSString stringWithFormat:@"%@ – %@",
                    [timeFormatter stringFromDate:event.startDate],
                    [timeFormatter stringFromDate:event.endDate]];
        }
        if ([calendar isDateInTomorrow:event.startDate]) {
            when = [NSString stringWithFormat:@"Tomorrow, %@", when];
        }
        UILabel *subtitle = GLTLabel(when, 13, UIFontWeightRegular,
                                    [UIColor colorWithWhite:1 alpha:0.6]);
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:
                            @[dot, GLTStack(@[title, subtitle], 2)]];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.spacing = 10;
        [rows addObject:row];
    }
    return GLTFill(@[GLTStack(rows, 12)]);
}

#pragma mark - Weather card

GLTPlatterContent *GLTMakeWeatherPlatter(void) {
    GLTWeather *weather = [GLTWeather sharedWeather];
    if (!weather.hasData) {
        return GLTFill(@[GLTStack(@[GLTCaption(@"Weather"),
                                   GLTInfoMessage(weather.problem ?: @"Loading the weather…")], 12)]);
    }
    NSString *place = weather.place.length ? weather.place : @"Current Location";
    UILabel *location = GLTLabel(place, 17, UIFontWeightSemibold, [UIColor whiteColor]);
    UILabel *condition = GLTLabel([GLTWeather descriptionForCode:weather.code], 14,
                                  UIFontWeightRegular, [UIColor whiteColor]);
    UILabel *feels = GLTLabel([NSString stringWithFormat:@"Feels like %@ · Rain %ld%%",
                               [GLTWeather temperatureString:weather.feelsLike], (long)weather.rainChance],
                              13, UIFontWeightRegular, [UIColor colorWithWhite:1 alpha:0.6]);
    UIImageView *glyph = [[UIImageView alloc] initWithImage:
                          GLTSymbol([GLTWeather symbolForCode:weather.code isDay:weather.isDay],
                                    30, UIImageSymbolWeightSemibold)];
    glyph.tintColor = [UIColor whiteColor];
    glyph.contentMode = UIViewContentModeTopLeft;
    NSMutableArray *details = [NSMutableArray arrayWithObjects:glyph, location, condition, feels, nil];
    NSDate *sunrise = weather.sunrises.firstObject;
    NSDate *sunset = weather.sunsets.firstObject;
    if (sunrise && sunset) {
        NSDateFormatter *sunFormatter = [NSDateFormatter new];
        sunFormatter.dateStyle = NSDateFormatterNoStyle;
        sunFormatter.timeStyle = NSDateFormatterShortStyle;
        [details addObject:GLTLabel([NSString stringWithFormat:@"Sunrise %@ · Sunset %@",
                                     [sunFormatter stringFromDate:sunrise], [sunFormatter stringFromDate:sunset]],
                                    13, UIFontWeightRegular, [UIColor colorWithWhite:1 alpha:0.6])];
    }
    UIStackView *left = GLTStack(details, 2);
    [left setCustomSpacing:6 afterView:glyph];
    UILabel *temperature = GLTLabel([GLTWeather temperatureString:weather.temperature],
                                    46, UIFontWeightLight, [UIColor whiteColor]);
    temperature.textAlignment = NSTextAlignmentRight;
    UILabel *range = GLTLabel([NSString stringWithFormat:@"H %@  L %@",
                               [GLTWeather temperatureString:weather.high],
                               [GLTWeather temperatureString:weather.low]],
                              13, UIFontWeightMedium, [UIColor colorWithWhite:1 alpha:0.6]);
    range.textAlignment = NSTextAlignmentRight;
    UIStackView *right = GLTStack(@[temperature, range], 0);
    right.alignment = UIStackViewAlignmentTrailing;
    UIStackView *headline = [[UIStackView alloc] initWithArrangedSubviews:@[left, right]];
    headline.axis = UILayoutConstraintAxisHorizontal;
    headline.spacing = 12;
    headline.alignment = UIStackViewAlignmentTop;

    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"j" options:0 locale:[NSLocale currentLocale]];
    NSMutableArray<UIView *> *hours = [NSMutableArray array];
    NSUInteger index = 0;
    for (GLTWeatherHour *hour in weather.hours) {
        UILabel *time = GLTLabel(index++ == 0 ? @"Now" : [formatter stringFromDate:hour.date],
                                 12, UIFontWeightMedium, [UIColor colorWithWhite:1 alpha:0.6]);
        time.textAlignment = NSTextAlignmentCenter;
        UIImageView *icon = [[UIImageView alloc] initWithImage:
                             GLTSymbol([GLTWeather symbolForCode:hour.code isDay:hour.isDay],
                                       18, UIImageSymbolWeightSemibold)];
        icon.tintColor = [UIColor whiteColor];
        icon.contentMode = UIViewContentModeCenter;
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        [icon.heightAnchor constraintEqualToConstant:26].active = YES;
        UILabel *value = GLTLabel([GLTWeather temperatureString:hour.temperature], 14,
                                  UIFontWeightSemibold, [UIColor whiteColor]);
        value.textAlignment = NSTextAlignmentCenter;
        UIStackView *column = GLTStack(@[time, icon, value], 4);
        column.alignment = UIStackViewAlignmentCenter;
        [hours addObject:column];
    }
    UIStackView *strip = [[UIStackView alloc] initWithArrangedSubviews:hours];
    strip.axis = UILayoutConstraintAxisHorizontal;
    strip.distribution = UIStackViewDistributionFillEqually;
    UILabel *attribution = GLTLabel(@"Weather data by Open-Meteo.com", 10,
                                    UIFontWeightRegular, [UIColor colorWithWhite:1 alpha:0.35]);
    attribution.textAlignment = NSTextAlignmentRight;
    UIStackView *stack = GLTStack(@[headline, strip, attribution], 14);
    [stack setCustomSpacing:8 afterView:strip];
    return GLTFill(@[stack]);
}

#pragma mark - Storage card

// Original 0x17fc0: free + inactive + purgeable pages, not speculative
// pages or an estimate based on this process's footprint.
typedef struct {
    long long storageFree, storageTotal, memoryFree, memoryTotal;
} GLTInfoSystemUsage;

static GLTInfoSystemUsage GLTInfoCurrentSystemUsage(void) {
    GLTInfoSystemUsage usage = {0};
    NSDictionary *attributes =
        [[NSFileManager defaultManager] attributesOfFileSystemForPath:@"/private/var" error:nil];
    usage.storageFree = [attributes[NSFileSystemFreeSize] longLongValue];
    usage.storageTotal = [attributes[NSFileSystemSize] longLongValue];
    mach_port_t host = mach_host_self();
    vm_size_t pageSize = 0;
    vm_statistics64_data_t stats = {0};
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    if (host_page_size(host, &pageSize) == KERN_SUCCESS &&
        host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&stats, &count) == KERN_SUCCESS) {
        natural_t pages = stats.free_count + stats.inactive_count + stats.purgeable_count;
        usage.memoryFree = (long long)((uint64_t)pages * pageSize);
    }
    // Unlike the original, release our send right after taking the snapshot.
    mach_port_deallocate(mach_task_self(), host);
    usage.memoryTotal = (long long)[NSProcessInfo processInfo].physicalMemory;
    return usage;
}

// Original 0x1277c: two ordinary UIViews form a clipped, six-point meter.
// It is not a UIProgressView (which has different intrinsic geometry).
static UIView *GLTInfoUsageRow(NSString *title, NSString *symbol, long long free,
                             long long total, UIColor *color) {
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    icon.tintColor = color;
    UILabel *name = GLTLabel(title, 15, UIFontWeightSemibold, [UIColor whiteColor]);
    NSString *value = [NSString stringWithFormat:@"%@ free of %@",
                      [NSByteCountFormatter stringFromByteCount:free countStyle:NSByteCountFormatterCountStyleFile],
                      [NSByteCountFormatter stringFromByteCount:total countStyle:NSByteCountFormatterCountStyleFile]];
    UILabel *capacity = GLTLabel(value, 13, UIFontWeightRegular, [UIColor colorWithWhite:1 alpha:0.6]);
    capacity.textAlignment = NSTextAlignmentRight;
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[icon, name, capacity]];
    header.axis = UILayoutConstraintAxisHorizontal;
    header.alignment = UIStackViewAlignmentCenter;
    header.spacing = 8;
    [icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [name setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIView *track = [UIView new];
    track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.2];
    track.layer.cornerRadius = 3;
    track.clipsToBounds = YES;
    track.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *fill = [UIView new];
    fill.backgroundColor = color;
    fill.translatesAutoresizingMaskIntoConstraints = NO;
    [track addSubview:fill];
    double used = total > 0 ? (double)(total - free) / (double)total : 0;
    double fraction = MIN(1.0, MAX(0.001, used));
    [NSLayoutConstraint activateConstraints:@[
        [track.heightAnchor constraintEqualToConstant:6],
        [fill.leadingAnchor constraintEqualToAnchor:track.leadingAnchor],
        [fill.topAnchor constraintEqualToAnchor:track.topAnchor],
        [fill.bottomAnchor constraintEqualToAnchor:track.bottomAnchor],
        [fill.widthAnchor constraintEqualToAnchor:track.widthAnchor multiplier:fraction],
    ]];
    return GLTStack(@[header, track], 8);
}

GLTPlatterContent *GLTMakeStoragePlatter(void) {
    GLTInfoSystemUsage usage = GLTInfoCurrentSystemUsage();
    UIView *storage = GLTInfoUsageRow(@"Storage", @"internaldrive.fill",
                                    usage.storageFree, usage.storageTotal, [UIColor systemBlueColor]);
    UIView *memory = GLTInfoUsageRow(@"Memory", @"memorychip.fill",
                                   usage.memoryFree, usage.memoryTotal, [UIColor systemPurpleColor]);
    return GLTFill(@[GLTStack(@[storage, memory], 18)]);
}

#pragma mark - Countdown card

// The original statistic block (0x1314c) is shared by Countdown and Unlocks.
static UIView *GLTInfoStatistic(NSString *value, NSString *phrase, NSString *detail) {
    UILabel *number = GLTLabel(value, 46, UIFontWeightLight, [UIColor whiteColor]);
    UILabel *caption = GLTLabel(phrase, 15, UIFontWeightSemibold, [UIColor whiteColor]);
    caption.numberOfLines = 2;
    NSMutableArray *rows = [NSMutableArray arrayWithObjects:number, caption, nil];
    if (detail) {
        [rows addObject:GLTLabel(detail, 13, UIFontWeightRegular, [UIColor colorWithWhite:1 alpha:0.6])];
    }
    return GLTStack(rows, 2);
}

GLTPlatterContent *GLTMakeCountdownPlatter(void) {
    GLTPrefs *prefs = [GLTPrefs sharedPrefs];
    NSMutableArray *rows = [NSMutableArray arrayWithObject:GLTCaption(@"Countdown")];
    if (!prefs.countdownDate) {
        [rows addObject:GLTInfoMessage(@"Set a date in Glint's settings.")];
        return GLTFill(@[GLTStack(rows, 10)]);
    }
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate *from = [calendar startOfDayForDate:[NSDate date]];
    NSDate *to = [calendar startOfDayForDate:prefs.countdownDate];
    NSInteger days = [[calendar components:NSCalendarUnitDay fromDate:from toDate:to options:0] day];
    NSString *title = prefs.countdownTitle.length ? prefs.countdownTitle : @"the date";
    NSString *phrase;
    if (days == 0) {
        phrase = [NSString stringWithFormat:@"%@ is today", title];
    } else if (days > 0) {
        phrase = [NSString stringWithFormat:@"%@ until %@", days == 1 ? @"day" : @"days", title];
    } else {
        phrase = [NSString stringWithFormat:@"%@ since %@", days == -1 ? @"day" : @"days", title];
    }
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateStyle = NSDateFormatterFullStyle;
    formatter.timeStyle = NSDateFormatterNoStyle;
    NSString *number = [NSString stringWithFormat:@"%ld", (long)(days < 0 ? -days : days)];
    [rows addObject:GLTInfoStatistic(number, phrase, [formatter stringFromDate:prefs.countdownDate])];
    return GLTFill(@[GLTStack(rows, 10)]);
}

#pragma mark - Unlocks card

GLTPlatterContent *GLTMakeUnlocksPlatter(void) {
    GLTUnlocks *unlocks = [GLTUnlocks sharedUnlocks];
    NSMutableArray *rows = [NSMutableArray arrayWithObject:GLTCaption(@"Unlocks")];
    NSString *phrase = unlocks.today == 1 ? @"unlock today" : @"unlocks today";
    NSString *yesterday = [NSString stringWithFormat:@"Yesterday: %ld", (long)unlocks.yesterday];
    [rows addObject:GLTInfoStatistic([NSString stringWithFormat:@"%ld", (long)unlocks.today],
                                   phrase, yesterday)];
    return GLTFill(@[GLTStack(rows, 10)]);
}

#pragma mark - Device card

GLTPlatterContent *GLTMakeDevicePlatter(GLTPillContent *summary) {
    (void)summary;
    NSMutableArray *columns = [NSMutableArray array];
    for (GLTDevice *device in GLTConnectedDevices()) {
        UIImageView *icon = [[UIImageView alloc] initWithImage:device.glyph];
        icon.tintColor = [UIColor whiteColor];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        [icon.heightAnchor constraintEqualToConstant:30].active = YES;
        UILabel *percent = GLTLabel(GLTPercentText(device.percent), 15, UIFontWeightSemibold,
                                    [UIColor whiteColor]);
        percent.textAlignment = NSTextAlignmentCenter;
        NSString *batterySymbol;
        if (device.charging) batterySymbol = @"battery.100.bolt";
        else if (device.percent < 0) batterySymbol = @"battery.100";
        else if (device.percent <= 20) batterySymbol = @"battery.25";
        else if (device.percent <= 60) batterySymbol = @"battery.50";
        else if (device.percent <= 85) batterySymbol = @"battery.75";
        else batterySymbol = @"battery.100";
        UIImageView *battery = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:batterySymbol]];
        battery.tintColor = !device.charging && device.percent >= 0 && device.percent <= 20
                            ? [UIColor systemRedColor] : [UIColor systemGreenColor];
        battery.contentMode = UIViewContentModeScaleAspectFit;
        UILabel *name = GLTLabel(device.name ?: @"", 12, UIFontWeightRegular,
                                 [UIColor colorWithWhite:1 alpha:0.6]);
        name.textAlignment = NSTextAlignmentCenter;
        name.numberOfLines = 2;
        NSMutableArray *parts = [NSMutableArray arrayWithObjects:icon, percent, battery, name, nil];
        if (device.details) {
            UILabel *details = GLTLabel(device.details, 11, UIFontWeightMedium,
                                        [UIColor colorWithWhite:1 alpha:0.6]);
            details.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
            details.textAlignment = NSTextAlignmentCenter;
            details.numberOfLines = 2;
            [parts addObject:details];
        }
        UIStackView *column = GLTStack(parts, 6);
        column.alignment = UIStackViewAlignmentCenter;
        [columns addObject:column];
    }
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:columns];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.spacing = 8;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.alignment = UIStackViewAlignmentTop;
    return GLTFill(@[stack]);
}
