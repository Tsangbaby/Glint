//
//  GLTController.h
//  Glint (reconstructed interface)
//
//  Recovered from ObjC metadata of Glint.dylib 1.6.3
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>


@interface GLTController : NSObject
{
    GLTWindow *                    _window; // 0x08
    NSHashTable *                  _clockViews; // 0x10
    NSHashTable *                  _dateViews; // 0x18
    CGRect                         _anchorFrame; // 0x20
    UIView *                       _touchView; // 0x40
    UIView *                       _pickerView; // 0x48
    NSString *                     _shownKind; // 0x50
    UIWindow *                     _previousKeyWindow; // 0x58
    NSTimer *                      _timer; // 0x60
    NSDateFormatter *              _timeFormatter; // 0x68
    NSDate *                       _volumeUntil; // 0x78
    float                          _volume; // 0x80
    GLTNotification *              _notification; // 0x88
    NSDate *                       _notificationUntil; // 0x90
    NSMutableArray *               _pendingNotifications; // 0x98
    GLTPlatterView *               _platterView; // 0xc8
    UIControl *                    _dismissView; // 0xd0
    __weak GLTPlatterContent *       _weatherPlatterContent; // current Weather content identity only
}

@property (nonatomic, strong, readonly) NSString * shownKind;

#pragma mark - class methods
+ (GLTController *)sharedController;

#pragma mark - instance methods
- (instancetype)init;
- (void)start;
- (BOOL)canPresentOverlay;
- (void)moveWindowToScene:(UIWindowScene *)arg1;
- (void)keyboardFrameChanged:(NSNotification *)arg1;
- (void)prefsChanged;
- (void)tick;
- (BOOL)wantsWeather;
- (void)showVolume:(float)arg1;
- (BOOL)showsVolume;
- (void)showNotification:(GLTNotification *)arg1;
- (BOOL)showsNotification;
- (void)updateAfter:(double)arg1;
- (NSInteger)currentPill;
- (void)update;
- (void)registerClockView:(UIView *)arg1 dateView:(UIView *)arg2;
- (UIView *)visibleClock;
- (CGRect)frameOfClock:(UIView *)arg1;
- (void)layoutTouchView;
- (BOOL)showsPlainTime;
- (void)renderClocks;
- (GLTPillContent *)pillContent;
- (GLTPillContent *)contentForPill:(NSInteger)arg1;
- (GLTPillContent *)mediaContent;
- (GLTPillContent *)weatherContent;
- (NSString *)stringForUpcomingDate:(NSDate *)arg1;
- (GLTPillContent *)alarmContent;
- (GLTPillContent *)storageContent;
- (NSInteger)cutout;
- (GLTPlatterContent *)platterContent;
- (void)openPlatter:(GLTPlatterContent *)arg1;
- (void)closePlatter;
- (void)fitPlatterToContent;
- (void)closePlatterAnimated:(BOOL)arg1;
- (void)clockTapped;
- (void)clockLongPressed:(UILongPressGestureRecognizer *)arg1;
- (UIView *)pickerRowForPill:(NSInteger)arg1 font:(UIFont *)arg2;
- (UIView *)pickerCellForPill:(NSInteger)arg1 font:(UIFont *)arg2 width:(CGFloat)arg3;
- (void)showPicker;
- (void)pickerRowTapped:(UITapGestureRecognizer *)arg1;
- (void)hidePicker;

@end
