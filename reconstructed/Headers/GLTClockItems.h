//
//  GLTClockItems.h
//  Glint (reconstructed interface)
//
//  Recovered from ObjC metadata of Glint.dylib 1.6.3
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

@class MTAlarmManager, MTTimerManager;


@interface GLTClockItems : NSObject
{
    MTAlarmManager *               _alarmManager; // 0x08
    MTTimerManager *               _timerManager; // 0x10
    NSObject<OS_dispatch_queue> *  _queue; // 0x18
    BOOL                           _refreshing; // 0x20
    NSArray *                      _alarms; // 0x28
    NSDate *                       _timerFireDate; // 0x30
    double                         _pausedTimerRemaining; // 0x38
    double                         _timerDuration; // 0x40
}

@property (nonatomic, strong, readonly) NSArray * alarms;
@property (nonatomic, strong, readonly) NSDate * timerFireDate;
@property (nonatomic, assign, readonly) double pausedTimerRemaining;
@property (nonatomic, assign, readonly) double timerDuration;

#pragma mark - class methods
+ (GLTClockItems *)sharedItems;

#pragma mark - instance methods
- (instancetype)init;
- (void)refresh;

@end
