//
//  GLTInfoPlatters.m
//
//  Read-only weather, storage/memory, and notification cards.
//  Factories recovered from 0x10ad8 (weather), 0x12600 (storage), and
//  0x10640 (notification). Layout remains a thin view over controller data.
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

#pragma mark - Weather card

GLTPlatterContent *GLTMakeWeatherPlatter(void) {
    GLTWeather *weather = [GLTWeather sharedWeather];
    if (!weather.hasData) {
        return GLTFill(@[GLTStack(@[GLTCaption(GLTLocalizedString(@"Weather")),
                                   GLTInfoMessage(weather.problem ?: GLTLocalizedString(@"Loading the weather…"))], 12)]);
    }
    NSString *place = weather.place.length ? weather.place : GLTLocalizedString(@"Current Location");
    UILabel *location = GLTLabel(place, 17, UIFontWeightSemibold, [UIColor whiteColor]);
    UILabel *condition = GLTLabel([GLTWeather descriptionForCode:weather.code], 14,
                                  UIFontWeightRegular, [UIColor whiteColor]);
    UILabel *feels = GLTLabel([NSString stringWithFormat:GLTLocalizedString(@"Feels like %@ · Rain %ld%%"),
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
        [details addObject:GLTLabel([NSString stringWithFormat:GLTLocalizedString(@"Sunrise %@ · Sunset %@"),
                                     [sunFormatter stringFromDate:sunrise], [sunFormatter stringFromDate:sunset]],
                                    13, UIFontWeightRegular, [UIColor colorWithWhite:1 alpha:0.6])];
    }
    UIStackView *left = GLTStack(details, 2);
    [left setCustomSpacing:6 afterView:glyph];
    UILabel *temperature = GLTLabel([GLTWeather temperatureString:weather.temperature],
                                    46, UIFontWeightLight, [UIColor whiteColor]);
    temperature.textAlignment = NSTextAlignmentRight;
    UILabel *range = GLTLabel([NSString stringWithFormat:GLTLocalizedString(@"H %@  L %@"),
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
        UILabel *time = GLTLabel(index++ == 0 ? GLTLocalizedString(@"Now") : [formatter stringFromDate:hour.date],
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
    UILabel *attribution = GLTLabel(GLTLocalizedString(@"Weather data by Open-Meteo.com"), 10,
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
    NSString *value = [NSString stringWithFormat:GLTLocalizedString(@"%@ free of %@"),
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
    UIView *storage = GLTInfoUsageRow(GLTLocalizedString(@"Storage"), @"internaldrive.fill",
                                    usage.storageFree, usage.storageTotal, [UIColor systemBlueColor]);
    UIView *memory = GLTInfoUsageRow(GLTLocalizedString(@"Memory"), @"memorychip.fill",
                                   usage.memoryFree, usage.memoryTotal, [UIColor systemPurpleColor]);
    return GLTFill(@[GLTStack(@[storage, memory], 18)]);
}
