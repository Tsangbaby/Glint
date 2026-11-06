//
//  GlintPrivate.h
//  Internal vocabulary shared between the Glint translation units.
//
//  The original binary keeps all of this in file-static constants and
//  file-static factory functions; the values below are the exact strings and
//  numbers recovered from Glint.dylib 1.6.3.
//

#ifndef GLINT_PRIVATE_H
#define GLINT_PRIVATE_H

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "GLTRuntime.h"

@class GLTPillContent, GLTPlatterContent, GLTPlatterView, GLTDevice, GLTNotification, GLTRecipient;

#pragma mark - Domains and notifications

// User defaults domain shared with the preference bundle.
static NSString *const kGLTPrefsDomain = @"com.antonym.glint";

// Darwin notification posted by every control in the preference bundle.
static NSString *const kGLTReloadNotification = @"com.antonym.glint/reload";

// Posted by the data providers when their contents change.
static NSString *const GLTSourcesDidChangeNotification = @"GLTSourcesDidChangeNotification";
static NSString *const GLTPrefsDidChangeNotification   = @"GLTPrefsDidChangeNotification";

// Unlock counter persistence (see GLTUnlocks).
static NSString *const kGLTUnlocksDomain = @"com.antonym.glint.unlocks";
// Recent recipients for the Quick Message card (see GLTRecipient).
static NSString *const kGLTRecentsDomain = @"com.antonym.glint.recents";

#pragma mark - Pill identifiers
//
// The numeric values are persisted in the `pill` default and listed in the
// preference bundle's `validValues` array, so they must never be renumbered.

typedef NS_ENUM(NSInteger, GLTPill) {
    GLTPillTime            = 0,
    GLTPillDate            = 1,
    GLTPillBattery         = 2,
    GLTPillNetwork         = 3,
    GLTPillNowPlaying      = 4,
    GLTPillCalendar        = 5,
    GLTPillReminders       = 6,
    GLTPillWeather         = 7,
    GLTPillAlarm           = 8,
    GLTPillNextEvent       = 9,
    GLTPillSun             = 10,
    GLTPillStorage         = 11,
    GLTPillCountdown       = 12,
    GLTPillUnlocks         = 13,
    GLTPillQuickMessage    = 14,
};

#pragma mark - Platter factories
//
// Each platter view class ships a file-static builder in the original binary
// (they show up as unnamed sub-functions right after the class's
// .cxx_destruct). They are declared here so the controller can dispatch to
// them through a switch instead of a jump table.

GLTPlatterContent *GLTMakeMediaPlatter(void);
GLTPlatterContent *GLTMakeEventsPlatter(void);
GLTPlatterContent *GLTMakeRemindersPlatter(void);
GLTPlatterContent *GLTMakeWeatherPlatter(void);
GLTPlatterContent *GLTMakeClockPlatter(void);
GLTPlatterContent *GLTMakeStoragePlatter(void);
GLTPlatterContent *GLTMakeCountdownPlatter(void);
GLTPlatterContent *GLTMakeUnlocksPlatter(void);
GLTPlatterContent *GLTMakeComposePlatter(void);
GLTPlatterContent *GLTMakeNotificationPlatter(GLTNotification *notification);
GLTPlatterContent *GLTMakeDevicePlatter(GLTPillContent *summary);

#pragma mark - Data providers

// BCBatteryDeviceController snapshot, sorted with the phone first and
// accessories after it.
NSArray<GLTDevice *> *GLTConnectedDevices(void);

// Contacts lookup used by the composer.
NSArray<GLTRecipient *> *GLTSearchRecipients(NSString *query);
// Read-only suggestions; no contacts request, persistence write or submission.
NSArray<GLTRecipient *> *GLTRecentRecipientSuggestions(void);
BOOL GLTSendMessage(GLTRecipient *recipient, NSString *text);

#pragma mark - Small helpers

// Symbol image at a given point size, multicolour where the symbol supports it.
UIImage *GLTSymbol(NSString *name, CGFloat pointSize, UIImageSymbolWeight weight);

// "%.0f%%"-style battery text with the "--%" placeholder for unknown levels.
NSString *GLTPercentText(long long percent);

// "12.3 GB free of 118 GB" for the storage pill and card.
NSString *GLTStorageSummary(void);

#define GLTLog(fmt, ...) NSLog((@"[Glint] " fmt), ##__VA_ARGS__)

#pragma mark - Private API used by the tweak

// SpringBoard-only: launching by bundle identifier is not in the public SDK.
@interface UIApplication (GlintPrivate)
- (void)launchApplicationWithIdentifier:(NSString *)identifier suspended:(BOOL)suspended;
@end

// SpringBoard-only icon lookup, used for notification cards and the picker.
@interface UIImage (GlintPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)identifier
                                               format:(int)format
                                                scale:(CGFloat)scale;
@end

// Declarations describe the source call sites; runtime admission is checked separately.
@class NCNotificationContent, SBApplication;
@interface NCNotificationRequest : NSObject
- (NSString *)sectionIdentifier;
- (NCNotificationContent *)content;
@end
@interface NCNotificationContent : NSObject
- (NSString *)header;
- (NSString *)title;
- (NSString *)message;
@end
@interface SBApplication : NSObject
- (NSString *)displayName;
@end
@interface SBApplicationController : NSObject
+ (instancetype)sharedInstance;
- (SBApplication *)applicationWithBundleIdentifier:(NSString *)identifier;
@end
@interface SBMediaController : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isPlaying;
- (void)togglePlayPauseForEventSource:(NSInteger)source;
- (void)changeTrack:(NSInteger)direction eventSource:(NSInteger)source;
@end
@protocol GLTStatusBarTimeItem <NSObject>
- (UIView *)timeView;
- (UIView *)dateView;
- (UIView *)shortTimeView;
@end

#endif /* GLINT_PRIVATE_H */
