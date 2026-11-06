//
//  GLTClock.h
//  Glint (reconstructed interface)
//
//  Recovered from ObjC metadata of Glint.dylib 1.6.3
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>


@interface GLTClock : NSObject
{
}

#pragma mark - class methods
+ (BOOL)isStyled:(UIView *)arg1;
+ (BOOL)isRendering;
+ (UIColor *)systemTextColorForLabel:(UILabel *)label;
+ (UIColor *)foregroundColorForLabel:(UILabel *)label;
+ (void)setSystemTextColor:(UIColor *)color forLabel:(UILabel *)label;
+ (UIEdgeInsets)padding;
+ (double)outsetForLabel:(UIView *)arg1;
+ (UIView *)backgroundForLabel:(UIView *)arg1 create:(BOOL)arg2;
+ (void)layoutBackgroundOfLabel:(UIView *)arg1;
+ (NSDate *)visibleDateOfLabel:(UIView *)arg1;
+ (UIEdgeInsets)paddingForLabel:(UIView *)arg1;
+ (void)setCompanion:(UIView *)arg1 forLabel:(UIView *)arg2;
+ (UIView *)ownerOfLabel:(UIView *)arg1;
+ (void)setSystemText:(NSString *)arg1 forLabel:(UIView *)arg2;
+ (void)apply:(GLTPillContent *)arg1 toLabel:(UILabel *)arg2 background:(UIColor *)arg3 textColor:(UIColor *)arg4;
+ (void)apply:(GLTPillContent *)arg1 toLabel:(UILabel *)arg2 background:(UIColor *)arg3 textColor:(UIColor *)arg4 animated:(BOOL)arg5;
+ (void)fadeOutSnapshotOfLabel:(UIView *)arg1;
+ (void)fadeInLabel:(UIView *)arg1;
+ (void)restoreAllLabels;
+ (void)popLabel:(UIView *)arg1;

#pragma mark - instance methods

@end
