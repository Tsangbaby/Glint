//
//  GLTModels.m
//
//  The plain value objects plus the three lookups that need private frameworks:
//  accessory batteries (BCBatteryDeviceController), the contact/recents search
//  used by the composer, and the iMessage sender (IMCore).
//
//  Recovered from 0x16448 (devices), 0x1871c (contacts), 0x191e4 / 0x1938c
//  (iMessage), 0x17418 (alarm equality), 0x19b6c (opening an app).
//

#import "Glint.h"
#import "GlintPrivate.h"
#import <dlfcn.h>

#pragma mark - Battery devices

@interface BCBatteryDevice : NSObject
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *groupName;
@property (nonatomic, readonly) long long percentCharge;
@property (nonatomic, readonly, getter=isCharging) BOOL charging;
@property (nonatomic, readonly, getter=isInternal) BOOL internal;
@property (nonatomic, readonly) NSArray *parts;
@end

@interface BCBatteryDeviceController : NSObject
+ (instancetype)sharedInstance;
- (NSArray *)connectedDevices;
@end

// Substring -> SF Symbol, checked in order. The original keeps this as an
// array of arrays in __objc_arrayobj (0x2f1c0), 11 groups in total.
static NSString *GLTGlyphForDeviceName(NSString *name) {
    static NSArray<NSArray *> *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @[@[@"airpods max", @"airpodsmax"],
                  @[@"airpods pro", @"airpodspro"],
                  @[@"airpods"],
                  @[@"beats"],
                  @[@"watch", @"applewatch"],
                  @[@"pencil", @"applepencil"],
                  @[@"mouse", @"magicmouse"],
                  @[@"trackpad"],
                  @[@"keyboard"],
                  @[@"iphone"],
                  @[@"ipad"]];
    });

    NSString *lower = [name lowercaseString];
    NSArray<NSString *> *symbols = @[@"airpods.max", @"airpods.pro", @"airpods",
                                     @"beats.headphones", @"applewatch", @"applepencil",
                                     @"magicmouse", @"rectangle.and.hand.point.up.left",
                                     @"keyboard", @"iphone", @"ipad"];

    for (NSUInteger i = 0; i < table.count; i++) {
        for (NSString *needle in table[i]) {
            if ([lower containsString:needle]) {
                return symbols[i];
            }
        }
    }
    return @"headphones";
}

// Parts of a multi-piece accessory (AirPods L / R / Case) are folded into one
// row whose details string lists each piece.
static NSString *GLTDetailsForParts(NSArray *parts) {
    if (parts.count < 2) return nil;

    NSMutableArray<NSString *> *chunks = [NSMutableArray array];
    for (BCBatteryDevice *part in parts) {
        NSString *label = part.name;
        if (!label.length) continue;
        [chunks addObject:[NSString stringWithFormat:@"%@ %lld%%", label, part.percentCharge]];
    }
    return chunks.count ? [chunks componentsJoinedByString:@"  "] : nil;
}

NSArray<GLTDevice *> *GLTConnectedDevices(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/BatteryCenter.framework/BatteryCenter", RTLD_LAZY);
    });

    Class controllerClass = NSClassFromString(@"BCBatteryDeviceController");
    if (![controllerClass respondsToSelector:@selector(sharedInstance)]) return @[];

    NSMutableArray<GLTDevice *> *result = [NSMutableArray array];
    NSMutableDictionary<NSString *, GLTDevice *> *byIdentifier = [NSMutableDictionary dictionary];

    @try {
        for (BCBatteryDevice *device in [[controllerClass sharedInstance] connectedDevices]) {
            if (![device respondsToSelector:@selector(identifier)]) continue;

            NSString *identifier = device.identifier ?: [[NSUUID UUID] UUIDString];
            GLTDevice *entry = byIdentifier[identifier];

            if (!entry) {
                entry = [GLTDevice new];
                entry.identifier = identifier;
                entry.name = device.groupName.length ? device.groupName : device.name;
                entry.percent = device.percentCharge;
                entry.charging = device.charging;
                entry.internal = device.internal;
                entry.glyph = GLTSymbol(GLTGlyphForDeviceName(entry.name ?: @""), 15, UIFontWeightRegular);
                byIdentifier[identifier] = entry;
                [result addObject:entry];
            } else if (device.percentCharge > entry.percent) {
                entry.percent = device.percentCharge;
                entry.charging = entry.charging || device.charging;
            }

            if ([device respondsToSelector:@selector(parts)]) {
                NSString *details = GLTDetailsForParts(device.parts);
                if (details.length) entry.details = details;
            }
        }
    } @catch (NSException *exception) {
        GLTLog(@"battery devices: %@", exception);
    }

    // The phone itself is not part of connectedDevices on every build; append
    // it from UIDevice when missing.
    BOOL hasInternal = NO;
    for (GLTDevice *device in result) {
        if (device.internal) { hasInternal = YES; break; }
    }
    if (!hasInternal) {
        UIDevice *current = [UIDevice currentDevice];
        if (current.batteryLevel >= 0) {
            GLTDevice *phone = [GLTDevice new];
            phone.identifier = @"com.apple.internal";
            phone.name = current.name;
            phone.percent = (long long)lroundf(current.batteryLevel * 100.0f);
            phone.charging = current.batteryState == UIDeviceBatteryStateCharging
                          || current.batteryState == UIDeviceBatteryStateFull;
            phone.internal = YES;
            phone.glyph = GLTSymbol([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad
                                    ? @"ipad" : @"iphone", 15, UIFontWeightRegular);
            [result insertObject:phone atIndex:0];
        }
    }

    // Internal (the phone) first, then accessories by descending charge.
    [result sortUsingComparator:^NSComparisonResult(GLTDevice *a, GLTDevice *b) {
        if (a.internal != b.internal) return a.internal ? NSOrderedAscending : NSOrderedDescending;
        if (a.percent == b.percent) return NSOrderedSame;
        return a.percent > b.percent ? NSOrderedAscending : NSOrderedDescending;
    }];

    return result;
}

@implementation GLTDevice
@end

#pragma mark - Alarm

@implementation GLTAlarm

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[GLTAlarm class]]) return NO;

    GLTAlarm *other = object;
    if (![self.title isEqualToString:other.title]) return NO;
    if (self.fireDate && other.fireDate) return [self.fireDate isEqualToDate:other.fireDate];
    return self.fireDate == other.fireDate;
}

- (unsigned long long)hash {
    return self.title.hash ^ (unsigned long long)self.fireDate.timeIntervalSince1970;
}

@end

#pragma mark - Notification

@implementation GLTNotification

// Tapping the notification card launches the originating app.
- (void)open {
    if (!_bundleIdentifier.length) return;
    [[UIApplication sharedApplication] launchApplicationWithIdentifier:_bundleIdentifier
                                                             suspended:NO];
}

@end

#pragma mark - Weather hour

@implementation GLTWeatherHour
@end

#pragma mark - Recipients

// Contacts search: a query made only of phone characters is treated as a
// number, anything containing "@" as an address, otherwise as a name.
NSArray<GLTRecipient *> *GLTSearchRecipients(NSString *query) {
    NSString *trimmed = [query stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) return @[];

    NSMutableArray<GLTRecipient *> *results = [NSMutableArray array];

    NSCharacterSet *phoneCharacters = [NSCharacterSet characterSetWithCharactersInString:@"+0123456789 ()-."];
    BOOL looksLikeNumber = [[trimmed stringByTrimmingCharactersInSet:phoneCharacters] length] == 0;
    BOOL looksLikeEmail  = [trimmed containsString:@"@"];

    if (looksLikeNumber || looksLikeEmail) {
        GLTRecipient *direct = [GLTRecipient new];
        direct.name = nil;
        direct.address = trimmed;
        direct.detail = looksLikeEmail ? @"Email" : @"Number";
        [results addObject:direct];
    }

    CNContactStore *store = [CNContactStore new];
    NSArray *keys = @[CNContactGivenNameKey, CNContactFamilyNameKey,
                      CNContactOrganizationNameKey, CNContactPhoneNumbersKey,
                      CNContactEmailAddressesKey];
    NSPredicate *predicate = [CNContact predicateForContactsMatchingName:trimmed];
    NSError *error = nil;
    NSArray<CNContact *> *contacts = [store unifiedContactsMatchingPredicate:predicate
                                                                keysToFetch:keys
                                                                      error:&error];

    for (CNContact *contact in contacts) {
        NSString *name = [NSString stringWithFormat:@"%@ %@", contact.givenName ?: @"",
                          contact.familyName ?: @""];
        name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!name.length) name = contact.organizationName;

        if (looksLikeNumber || !looksLikeEmail) {
            for (CNLabeledValue<CNPhoneNumber *> *phone in contact.phoneNumbers) {
                GLTRecipient *recipient = [GLTRecipient new];
                recipient.name = name;
                recipient.address = phone.value.stringValue;
                recipient.detail = [CNLabeledValue localizedStringForLabel:phone.label] ?: @"phone";
                [results addObject:recipient];
                if (results.count >= 8) return results;
            }
        }
        if (looksLikeEmail || !looksLikeNumber) {
            for (CNLabeledValue<NSString *> *email in contact.emailAddresses) {
                GLTRecipient *recipient = [GLTRecipient new];
                recipient.name = name;
                recipient.address = email.value;
                recipient.detail = [CNLabeledValue localizedStringForLabel:email.label] ?: @"Email";
                [results addObject:recipient];
                if (results.count >= 8) return results;
            }
        }
    }

    return results;
}

@implementation GLTRecipient
@end

#pragma mark - Recent recipients

// Kept in the tweak's own defaults domain so the card can suggest the last few
// people without touching the contacts database.
#if !GLINT_VERIFICATION_BUILD
static NSArray<NSDictionary *> *GLTRecentRecipients(void) {
    CFPropertyListRef stored = CFPreferencesCopyAppValue(CFSTR("recipients"),
                                                         CFSTR("com.antonym.glint.recents"));
    NSArray *list = CFBridgingRelease(stored);
    return [list isKindOfClass:[NSArray class]] ? list : @[];
}

static void GLTRememberRecipient(GLTRecipient *recipient) {
    if (!recipient.address.length) return;

    NSMutableArray *list = [GLTRecentRecipients() mutableCopy];
    NSDictionary *entry = @{ @"name": recipient.name ?: @"",
                             @"address": recipient.address,
                             @"detail": recipient.detail ?: @"" };

    [list removeObject:entry];
    [list insertObject:entry atIndex:0];
    while (list.count > 5) [list removeLastObject];

    CFPreferencesSetAppValue(CFSTR("recipients"), (__bridge CFPropertyListRef)list,
                             CFSTR("com.antonym.glint.recents"));
    CFPreferencesAppSynchronize(CFSTR("com.antonym.glint.recents"));
}
#endif

#pragma mark - iMessage

// Sending goes through IMCore because the composer bypasses the Messages UI.
// Every call is guarded: the private API drifts between iOS releases and a
// failure must degrade to the system composer, not crash SpringBoard.
BOOL GLTSendMessage(GLTRecipient *recipient, NSString *text) {
#if GLINT_VERIFICATION_BUILD
    return NO; // No real message submission in the first-device candidate.
#else
    if (!recipient.address.length || !text.length) return NO;

    dlopen("/System/Library/PrivateFrameworks/IMCore.framework/IMCore", RTLD_LAZY);

    @try {
        Class daemonClass = NSClassFromString(@"IMDaemonController");
        id daemon = [daemonClass respondsToSelector:@selector(sharedController)]
            ? [daemonClass sharedController]
            : nil;
        if ([daemon respondsToSelector:@selector(connectToDaemonWithLaunch:capabilities:blockUntilConnected:)]) {
            [daemon connectToDaemonWithLaunch:0 capabilities:0 blockUntilConnected:YES];
        } else if ([daemon respondsToSelector:@selector(connectToDaemon)]) {
            [daemon connectToDaemon];
        }

        Class accountClass = NSClassFromString(@"IMAccountController");
        id accountController = [accountClass respondsToSelector:@selector(sharedInstance)]
            ? [accountClass sharedInstance]
            : nil;

        id account = nil;
        if ([recipient.address containsString:@"@"]) {
            account = [accountController respondsToSelector:@selector(activeIMessageAccount)]
                ? [accountController activeIMessageAccount]
                : nil;
        } else {
            account = [accountController respondsToSelector:@selector(activeSMSAccount)]
                ? [accountController activeSMSAccount]
                : nil;
        }
        if (!account) return NO;

        id handle = [account respondsToSelector:@selector(imHandleWithID:)]
            ? [account imHandleWithID:recipient.address]
            : nil;
        if (!handle) return NO;

        Class registryClass = NSClassFromString(@"IMChatRegistry");
        id registry = [registryClass respondsToSelector:@selector(sharedInstance)]
            ? [registryClass sharedInstance]
            : nil;
        id chat = [registry respondsToSelector:@selector(chatForIMHandle:)]
            ? [registry chatForIMHandle:handle]
            : nil;
        if (!chat) return NO;

        NSMutableAttributedString *body =
            [[NSMutableAttributedString alloc] initWithString:text];
        [body addAttribute:@"__kIMMessagePartAttributeName"
                    value:@0
                    range:NSMakeRange(0, body.length)];

        Class messageClass = NSClassFromString(@"IMMessage");
        id message = [messageClass instantMessageWithText:body
                                                    flags:0
                                         threadIdentifier:nil];
        if (!message) return NO;

        if ([chat respondsToSelector:@selector(sendMessage:)]) {
            [chat sendMessage:message];
        }

        GLTRememberRecipient(recipient);
        return YES;
    } @catch (NSException *exception) {
        GLTLog(@"Sending failed: %@", exception);
        return NO;
    }
#endif
}
