//
//  GLTPlatterView.h
//  Glint (reconstructed interface)
//
//  Recovered from ObjC metadata of Glint.dylib 1.6.3
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>


@interface GLTPlatterView : UIView
{
    UIVisualEffectView *           _blurView; // 0x08
    GLTPlatterContent *            _content; // 0x10
    double                         _topInset; // 0x18
    double                         _openWidth; // 0x20
}

@property (nonatomic, strong) GLTPlatterContent * content;
@property (nonatomic, assign) double topInset;
@property (nonatomic, assign) double openWidth;

#pragma mark - class methods
#pragma mark - instance methods
- (id)initWithFrame:(CGRect)arg1;
- (double)heightForWidth:(double)arg1;
- (void)layoutSubviews;

@end
