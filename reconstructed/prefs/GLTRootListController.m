//
//  GLTRootListController.m
//
//  Recovered from GlintPrefs 0x4000 (specifiers), 0x4060 (viewDidLoad) and
//  0x4354 (bannerView).
//

#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

// Posted by every control so the tweak reloads without a respring.
static NSString *const kGlintReloadNotification = @"com.antonym.glint/reload";

@interface GLTRootListController : PSListController
- (UIView *)bannerView;
@end

@interface GLTRootListController ()
@property (nonatomic, strong) UIView *headerView;
@end

// Always resolve strings in GlintPrefs, never the hosting Settings bundle.
// The English key is also the fallback for missing translations.
static NSString *GLTLocalizedSetting(NSBundle *bundle, NSString *english, NSString *table) {
    if (!english.length) return english;
    return [bundle localizedStringForKey:english value:english table:table];
}

static NSDictionary *GLTLocalizedTitles(NSBundle *bundle, NSDictionary *titles) {
    NSMutableDictionary *localized = [NSMutableDictionary dictionaryWithCapacity:titles.count];
    for (id value in titles) {
        localized[value] = GLTLocalizedSetting(bundle, titles[value], @"Root");
    }
    return localized;
}

@implementation GLTRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSBundle *bundle = [NSBundle bundleForClass:[GLTRootListController class]];
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self bundle:bundle];
        for (PSSpecifier *specifier in _specifiers) {
            specifier.name = GLTLocalizedSetting(bundle, specifier.name, @"Root");
            for (NSString *key in @[@"footerText", @"placeholder"]) {
                NSString *english = [specifier propertyForKey:key];
                if ([english isKindOfClass:[NSString class]]) {
                    [specifier setProperty:GLTLocalizedSetting(bundle, english, @"Root") forKey:key];
                }
            }

            // The loader has already built value->title maps. Localize those
            // maps (including the link-cell summary), not just validTitles;
            // PSListItemsController must retain the original stored values.
            if (specifier.titleDictionary) {
                specifier.titleDictionary = GLTLocalizedTitles(bundle, specifier.titleDictionary);
            }
            if (specifier.shortTitleDictionary) {
                specifier.shortTitleDictionary = GLTLocalizedTitles(bundle, specifier.shortTitleDictionary);
            }
        }
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.table.tableHeaderView = [self bannerView];

    // The banner carries the title, so the navigation bar is tinted to match
    // and its own title is hidden.
    UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = [UIColor colorWithRed:0.06 green:0.72 blue:0.51 alpha:1.0];
    appearance.shadowColor = nil;
    appearance.titleTextAttributes = @{ NSForegroundColorAttributeName: [UIColor clearColor] };

    self.navigationController.navigationBar.standardAppearance = appearance;
    self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    self.navigationController.navigationBar.compactAppearance = appearance;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kGlintReloadNotification,
                                         NULL, NULL, true);
}

// Teal header with the tweak name and its version.
- (UIView *)bannerView {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 190)];
    header.backgroundColor = [UIColor colorWithRed:0.06 green:0.72 blue:0.51 alpha:1.0];

    UILabel *title = [UILabel new];
    title.text = @"Glint";
    title.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    title.textColor = [UIColor whiteColor];

    NSString *version = [[NSBundle bundleForClass:[self class]]
                         objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    UILabel *subtitle = [UILabel new];
    subtitle.text = [NSString stringWithFormat:
                     GLTLocalizedSetting([NSBundle bundleForClass:[GLTRootListController class]],
                                         @"Version %@", @"Localizable"), version ?: @"1.6.3"];
    subtitle.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    subtitle.textColor = [UIColor colorWithWhite:1 alpha:0.85];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, subtitle]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 2;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
    ]];

    return header;
}

@end
