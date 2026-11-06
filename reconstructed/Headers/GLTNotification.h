//
//  GLTNotification.h
//  Glint (reconstructed interface)
//
//  Recovered from ObjC metadata of Glint.dylib 1.6.3
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>


@interface GLTNotification : NSObject
{
    NSString *                     _bundleIdentifier; // 0x08
    NSString *                     _appName; // 0x10
    UIImage *                      _icon; // 0x18
    NSString *                     _title; // 0x20
    NSString *                     _message; // 0x28
}

@property (nonatomic, copy) NSString * bundleIdentifier;
@property (nonatomic, copy) NSString * appName;
@property (nonatomic, strong) UIImage * icon;
@property (nonatomic, copy) NSString * title;
@property (nonatomic, copy) NSString * message;

#pragma mark - class methods
#pragma mark - instance methods
- (void)open;

@end
