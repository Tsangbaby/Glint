//
//  GLTNotificationPlatterView.h
//  Glint (reconstructed interface)
//
//  Recovered from ObjC metadata of Glint.dylib 1.6.3
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

#import "GLTPlatterContent.h"

@interface GLTNotificationPlatterView : GLTPlatterContent
{
    GLTNotification *              _notification; // 0x18
    id /* block */                 _closeHandler; // 0x08
    id /* block */                 _resizeHandler; // 0x10
}

@property (nonatomic, strong) GLTNotification * notification;

#pragma mark - class methods
#pragma mark - instance methods
- (void)open;

@end
