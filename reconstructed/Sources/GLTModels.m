//
//  GLTModels.m
//
//  Plain value objects, contact/recents lookup for the composer, and
//  the iMessage sender (IMCore).
//
//  Recovered from 0x1871c (contacts), 0x191e4 / 0x1938c
//  (iMessage), 0x17418 (alarm equality), 0x19b6c (opening an app).
//

#import "Glint.h"
#import "GlintPrivate.h"
#import <dlfcn.h>

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
        direct.detail = looksLikeEmail ? GLTLocalizedString(@"Email") : GLTLocalizedString(@"Number");
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
                recipient.detail = [CNLabeledValue localizedStringForLabel:phone.label] ?: GLTLocalizedString(@"phone");
                [results addObject:recipient];
                if (results.count >= 8) return results;
            }
        }
        if (looksLikeEmail || !looksLikeNumber) {
            for (CNLabeledValue<NSString *> *email in contact.emailAddresses) {
                GLTRecipient *recipient = [GLTRecipient new];
                recipient.name = name;
                recipient.address = email.value;
                recipient.detail = [CNLabeledValue localizedStringForLabel:email.label] ?: GLTLocalizedString(@"Email");
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
static NSArray<NSDictionary *> *GLTRecentRecipients(void) {
    CFPreferencesAppSynchronize(CFSTR("com.antonym.glint.recents"));
    CFPropertyListRef stored = CFPreferencesCopyAppValue(CFSTR("recipients"),
                                                         CFSTR("com.antonym.glint.recents"));
    NSArray *list = CFBridgingRelease(stored);
    return [list isKindOfClass:[NSArray class]] ? list : @[];
}

// Original 0x18f08 returns typed value objects for the card. Reading existing
// recents is separate from the verification build's disabled write/send path.
NSArray<GLTRecipient *> *GLTRecentRecipientSuggestions(void) {
    NSMutableArray<GLTRecipient *> *result = [NSMutableArray array];
    for (id stored in GLTRecentRecipients()) {
        if (![stored isKindOfClass:[NSDictionary class]]) continue;
        NSString *address = stored[@"address"];
        if (![address isKindOfClass:[NSString class]]) continue;
        GLTRecipient *recipient = [GLTRecipient new];
        recipient.address = address;
        // Invalid optional values degrade to the original address fallback.
        recipient.name = [stored[@"name"] isKindOfClass:[NSString class]] ? stored[@"name"] : address;
        recipient.detail = [stored[@"detail"] isKindOfClass:[NSString class]] ? stored[@"detail"] : address;
        [result addObject:recipient];
    }
    return result;
}

#if !GLINT_VERIFICATION_BUILD
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
