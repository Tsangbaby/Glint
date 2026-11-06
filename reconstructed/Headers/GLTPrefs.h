//
//  GLTPrefs.h
//  Glint (reconstructed interface)
//
//  Recovered from ObjC metadata of Glint.dylib 1.6.3
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>


@interface GLTPrefs : NSObject
{
    BOOL                           _enabled; // 0x08
    BOOL                           _tapToCycle; // 0x09
    BOOL                           _showSeconds; // 0x0a
    BOOL                           _showMediaWhilePlaying; // 0x0b
    BOOL                           _replaceBanners; // 0x0c
    BOOL                           _deviceConnections; // 0x0d
    BOOL                           _replaceVolumeHUD; // 0x0e
    UIColor *                      _backgroundColor; // 0x10
    UIColor *                      _textColor; // 0x18
    double                         _notificationDuration; // 0x20
    NSString *                     _weatherCity; // 0x28
    NSString *                     _countdownTitle; // 0x30
    NSDate *                       _countdownDate; // 0x38
    double                         _volumeDuration; // 0x40
    long long                      _pill; // 0x48
}

@property (nonatomic, assign) long long pill;
@property (nonatomic, assign, readonly) BOOL enabled;
@property (nonatomic, assign, readonly) BOOL tapToCycle;
@property (nonatomic, strong, readonly) UIColor * backgroundColor;
@property (nonatomic, strong, readonly) UIColor * textColor;
@property (nonatomic, assign, readonly) BOOL showSeconds;
@property (nonatomic, assign, readonly) BOOL showMediaWhilePlaying;
@property (nonatomic, assign, readonly) BOOL replaceBanners;
@property (nonatomic, assign, readonly) double notificationDuration;
@property (nonatomic, assign, readonly) BOOL deviceConnections;
@property (nonatomic, strong, readonly) NSString * weatherCity;
@property (nonatomic, strong, readonly) NSString * countdownTitle;
@property (nonatomic, strong, readonly) NSDate * countdownDate;
@property (nonatomic, assign, readonly) BOOL replaceVolumeHUD;
@property (nonatomic, assign, readonly) double volumeDuration;

#pragma mark - class methods
+ (GLTPrefs *)sharedPrefs;
+ (NSArray *)pillOrder;
+ (NSString *)nameForPill:(NSInteger)arg1;
+ (NSString *)symbolForPill:(NSInteger)arg1;

#pragma mark - instance methods
- (id)objectForKey:(NSString *)arg1;
- (BOOL)boolForKey:(NSString *)arg1 fallback:(BOOL)arg2;
- (double)doubleForKey:(NSString *)arg1 fallback:(double)arg2 min:(double)arg3 max:(double)arg4;
- (void)reload;

@end
