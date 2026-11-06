//
//  GLTWindow.h
//  Glint (reconstructed interface)
//
//  Recovered from ObjC metadata of Glint.dylib 1.6.3
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>


@interface GLTWindow : UIWindow
{
    BOOL                           _acceptsKeyboard; // 0x08
    CGRect                         _keyboardFrame; // 0x10
}

@property (nonatomic, assign) BOOL acceptsKeyboard;
@property (nonatomic, assign) CGRect keyboardFrame;

#pragma mark - class methods
#pragma mark - instance methods
- (UIView *)hitTest:(CGPoint)arg1 withEvent:(UIEvent *)arg2;
- (BOOL)canBecomeKeyWindow;
- (BOOL)_shouldCreateContextAsSecure;

@end
