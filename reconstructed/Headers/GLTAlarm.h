//
//  GLTAlarm.h
//  Glint (reconstructed interface)
//
//  Recovered from ObjC metadata of Glint.dylib 1.6.3
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>


@interface GLTAlarm : NSObject
{
    NSString *                     _title; // 0x08
    NSDate *                       _fireDate; // 0x10
}

@property (nonatomic, copy) NSString * title;
@property (nonatomic, strong) NSDate * fireDate;

#pragma mark - class methods
#pragma mark - instance methods
- (BOOL)isEqual:(id)arg1;
- (unsigned long long)hash;

@end
