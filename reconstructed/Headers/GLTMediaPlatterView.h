//
//  GLTMediaPlatterView.h
//  Glint (reconstructed interface)
//
//  Recovered from ObjC metadata of Glint.dylib 1.6.3
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

#import "GLTPlatterContent.h"

@interface GLTMediaPlatterView : GLTPlatterContent
{
    UIImageView *                  _artworkView; // 0x18
    UILabel *                      _titleLabel; // 0x20
    UILabel *                      _artistLabel; // 0x28
    UIView *                       _track; // 0x30
    UIView *                       _fill; // 0x38
    UILabel *                      _elapsedLabel; // 0x40
    UILabel *                      _remainingLabel; // 0x48
    UIButton *                     _playButton; // 0x50
    NSTimer *                      _timer; // 0x58
    double                         _fraction; // 0x60
    id /* block */                 _closeHandler; // 0x08
    id /* block */                 _resizeHandler; // 0x10
}

#pragma mark - class methods
#pragma mark - instance methods
- (id)initWithFrame:(CGRect)arg1;
- (UIButton *)controlWithSymbol:(NSString *)arg1 size:(double)arg2 action:(SEL)arg3;
- (void)didMoveToWindow;
- (void)refresh;
- (void)layoutSubviews;
- (void)playPause;
- (void)next;
- (void)previous;

@end
