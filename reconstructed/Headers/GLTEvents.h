//
//  GLTEvents.h
//  Glint (reconstructed interface)
//
//  Recovered from ObjC metadata of Glint.dylib 1.6.3
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>


@interface GLTEvents : NSObject
{
    EKEventStore *                 _store; // 0x08
    NSArray *                      _upcomingEvents; // 0x10
    NSArray *                      _reminders; // 0x18
}

@property (nonatomic, strong, readonly) NSArray * upcomingEvents;
@property (nonatomic, strong, readonly) NSArray * reminders;

#pragma mark - class methods
+ (GLTEvents *)sharedEvents;

#pragma mark - instance methods
- (instancetype)init;
- (void)requestAccess;
- (BOOL)hasCalendarAccess;
- (BOOL)hasRemindersAccess;
- (void)refresh;
- (void)completeReminder:(EKReminder *)arg1;

@end
