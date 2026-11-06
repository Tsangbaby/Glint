//
//  GLTPillContent.h
//  Glint (reconstructed interface)
//
//  Recovered from ObjC metadata of Glint.dylib 1.6.3
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>


@interface GLTPillContent : NSObject
{
    UIImage *                      _image; // 0x08
    UIColor *                      _imageTint; // 0x10
    NSString *                     _text; // 0x18
    long long                      _badge; // 0x20
    double                         _progress; // 0x28
}

@property (nonatomic, strong) UIImage * image;
@property (nonatomic, strong) UIColor * imageTint;
@property (nonatomic, copy) NSString * text;
@property (nonatomic, assign) long long badge;
@property (nonatomic, assign) double progress;

#pragma mark - class methods
+ (GLTPillContent *)contentWithSymbol:(NSString *)arg1 text:(NSString *)arg2;

#pragma mark - instance methods
- (instancetype)init;
- (NSAttributedString *)attributedStringWithFont:(UIFont *)arg1 color:(UIColor *)arg2;

@end
