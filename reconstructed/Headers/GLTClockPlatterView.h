//
//  GLTClockPlatterView.h
//  Glint (reconstructed interface)
//
//  Recovered from ObjC metadata of Glint.dylib 1.6.3
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

#import "GLTPlatterContent.h"

@interface GLTClockPlatterView : GLTPlatterContent
{
    UIStackView *                  _stack; // 0x18
    UILabel *                      _countdown; // 0x20
    UIView *                       _track; // 0x28
    UIView *                       _fill; // 0x30
    NSTimer *                      _timer; // 0x38
    id /* block */                 _closeHandler; // 0x08
    id /* block */                 _resizeHandler; // 0x10
}

#pragma mark - class methods
#pragma mark - instance methods
- (id)initWithFrame:(CGRect)arg1;
- (void)didMoveToWindow;
- (void)rebuild;
- (void)tick;
- (void)layoutSubviews;

@end
