//
//  GLTCells.m
//  GLTSliderCell + GLTColorCell + GLTDateCell
//
//  The three custom cells referenced by Root.plist via `cellClass`.
//  Recovered from GlintPrefs 0x4758 (slider), 0x4fd8 (colour), 0x53ac (date).
//

#import <Preferences/PSTableCell.h>
#import <Preferences/PSSpecifier.h>

static NSString *const kGlintReload = @"com.antonym.glint/reload";

#pragma mark - Shared persistence

static id GLTReadValue(NSString *domain, NSString *key) {
    if (!domain || !key) return nil;
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)domain);
    return CFBridgingRelease(value);
}

static void GLTWriteValue(NSString *domain, NSString *key, id value) {
    if (!domain || !key) return;

    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)domain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kGlintReload,
                                         NULL, NULL, true);
}

static UIColor *GLTColorFromHex(NSString *hex) {
    NSString *clean = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (clean.length != 6) return nil;

    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexInt:&rgb]) return nil;

    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

static NSString *GLTHexFromColor(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) return @"#000000";
    return [NSString stringWithFormat:@"#%02X%02X%02X",
            (unsigned)(r * 255.0), (unsigned)(g * 255.0), (unsigned)(b * 255.0)];
}

#pragma mark - Slider

@interface GLTSliderCell : PSTableCell
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, assign) float step;
@property (nonatomic, copy) NSString *format;
@end

@implementation GLTSliderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier
                    specifier:(PSSpecifier *)specifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (!self) return nil;

    _slider = [UISlider new];
    _slider.translatesAutoresizingMaskIntoConstraints = NO;
    [_slider addTarget:self action:@selector(sliderChanged)
      forControlEvents:UIControlEventValueChanged];
    [_slider addTarget:self action:@selector(sliderReleased)
      forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.contentView addSubview:_slider];

    _valueLabel = [UILabel new];
    _valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    _valueLabel.textColor = [UIColor secondaryLabelColor];
    _valueLabel.textAlignment = NSTextAlignmentRight;
    _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_valueLabel setContentHuggingPriority:UILayoutPriorityRequired
                                   forAxis:UILayoutConstraintAxisHorizontal];
    [self.contentView addSubview:_valueLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_slider.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [_slider.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_valueLabel.leadingAnchor constraintEqualToAnchor:_slider.trailingAnchor constant:12],
        [_valueLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [_valueLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_valueLabel.widthAnchor constraintEqualToConstant:52],
    ]];

    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];

    NSDictionary *properties = specifier.properties;
    _step = [properties[@"step"] floatValue] ?: 0.1f;
    _format = properties[@"format"] ?: @"%.1f";

    _slider.minimumValue = [properties[@"min"] floatValue];
    _slider.maximumValue = [properties[@"max"] floatValue];

    NSNumber *stored = GLTReadValue(properties[@"defaults"], properties[@"key"]);
    _slider.value = stored ? stored.floatValue : [properties[@"default"] floatValue];

    [self updateLabel];
}

- (float)snappedValue {
    if (_step <= 0) return _slider.value;
    return roundf(_slider.value / _step) * _step;
}

- (void)updateLabel {
    _valueLabel.text = [NSString stringWithFormat:_format ?: @"%.1f", [self snappedValue]];
}

- (void)sliderChanged {
    [self updateLabel];
}

- (void)sliderReleased {
    NSDictionary *properties = self.specifier.properties;
    GLTWriteValue(properties[@"defaults"], properties[@"key"], @([self snappedValue]));
}

- (void).cxx_destruct {
    // ARC handles the strong properties.
}

@end

#pragma mark - Colour

@interface GLTColorCell : PSTableCell
@property (nonatomic, strong) UIColorWell *colorWell;
@end

@implementation GLTColorCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier
                    specifier:(PSSpecifier *)specifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (!self) return nil;

    _colorWell = [UIColorWell new];
    _colorWell.supportsAlpha = NO;
    _colorWell.translatesAutoresizingMaskIntoConstraints = NO;
    [_colorWell addTarget:self action:@selector(colorChanged)
         forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:_colorWell];

    [NSLayoutConstraint activateConstraints:@[
        [_colorWell.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [_colorWell.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_colorWell.widthAnchor constraintEqualToConstant:32],
        [_colorWell.heightAnchor constraintEqualToConstant:32],
    ]];

    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];

    NSDictionary *properties = specifier.properties;
    NSString *stored = GLTReadValue(properties[@"defaults"], properties[@"key"]);
    if (![stored isKindOfClass:[NSString class]]) stored = properties[@"default"];

    _colorWell.selectedColor = GLTColorFromHex(stored) ?: [UIColor blackColor];
}

- (void)colorChanged {
    NSDictionary *properties = self.specifier.properties;
    GLTWriteValue(properties[@"defaults"], properties[@"key"],
                  GLTHexFromColor(_colorWell.selectedColor));
}

- (void).cxx_destruct {
}

@end

#pragma mark - Date

@interface GLTDateCell : PSTableCell
@property (nonatomic, strong) UIDatePicker *picker;
@end

@implementation GLTDateCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier
                    specifier:(PSSpecifier *)specifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (!self) return nil;

    _picker = [UIDatePicker new];
    _picker.datePickerMode = UIDatePickerModeDate;
    if (@available(iOS 14, *)) {
        _picker.preferredDatePickerStyle = UIDatePickerStyleCompact;
    }
    _picker.translatesAutoresizingMaskIntoConstraints = NO;
    [_picker addTarget:self action:@selector(dateChanged)
      forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:_picker];

    [NSLayoutConstraint activateConstraints:@[
        [_picker.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [_picker.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
    ]];

    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];

    NSDictionary *properties = specifier.properties;
    NSDate *stored = GLTReadValue(properties[@"defaults"], properties[@"key"]);
    _picker.date = [stored isKindOfClass:[NSDate class]] ? stored : [NSDate date];
}

- (void)dateChanged {
    NSDictionary *properties = self.specifier.properties;
    GLTWriteValue(properties[@"defaults"], properties[@"key"], _picker.date);
}

- (void).cxx_destruct {
}

@end
