//
//  GLTClock.m
//
//  The styling engine. Glint does not add a view to the status bar: it paints
//  into the existing clock label and gives that label a companion background
//  view. Everything here is keyed off the label via associated objects, so no
//  subclassing or ivar injection is needed.
//
//  Recovered from 0xc3b4…0xdb28.
//

#import "Glint.h"

// Associated-object keys (the original keeps three static bytes in __bss at
// 0x34f30 / 0x34f32 / 0x34f58).
static char kGLTStyledKey;
static char kGLTBackgroundKey;
static char kGLTSystemTextKey;
static char kGLTSystemTextColorKey;

// Weak set of every label Glint is currently drawing into, and a weak-to-weak
// map from a label to its companion (the date label under the time).
static NSHashTable *GLTStyledLabels(void) {
    static NSHashTable *labels;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ labels = [NSHashTable weakObjectsHashTable]; });
    return labels;
}

static NSMapTable *GLTCompanions(void) {
    static NSMapTable *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ map = [NSMapTable weakToWeakObjectsMapTable]; });
    return map;
}

// Single global re-entrancy guard: while it is set, the setText: /
// setAttributedText: / setTextColor: hooks stay out of the way.
static BOOL _rendering;

@implementation GLTClock

+ (BOOL)isRendering {
    return _rendering;
}

+ (BOOL)isStyled:(UIView *)label {
    NSNumber *flag = objc_getAssociatedObject(label, &kGLTStyledKey);
    return flag.boolValue;
}

#pragma mark - Metrics

+ (UIColor *)systemTextColorForLabel:(UILabel *)label {
    return objc_getAssociatedObject(label, &kGLTSystemTextColorKey);
}

+ (UIColor *)foregroundColorForLabel:(UILabel *)label {
    GLTPrefs *prefs = [GLTPrefs sharedPrefs];
    if (prefs.backgroundOpacity == 0.0) {
        return [self systemTextColorForLabel:label] ?: label.textColor ?: prefs.textColor;
    }
    return prefs.textColor;
}

+ (void)setSystemTextColor:(UIColor *)color forLabel:(UILabel *)label {
    if (!color) return;
    objc_setAssociatedObject(label, &kGLTSystemTextColorKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!_rendering && [self isStyled:label] && [GLTPrefs sharedPrefs].backgroundOpacity == 0.0) {
        NSMutableAttributedString *string = [label.attributedText mutableCopy];
        if (string.length) {
            [string addAttribute:NSForegroundColorAttributeName value:color range:NSMakeRange(0, string.length)];
            _rendering = YES;
            label.attributedText = string;
            _rendering = NO;
        }
    }
}

// Horizontal breathing room on both sides of the pill.
+ (UIEdgeInsets)padding {
    return UIEdgeInsetsMake(0, 9, 0, 9);
}

// Vertical overhang of the background view. Scales with how far the clock sits
// from the top of the screen, clamped to a 1.5…4.5pt band.
+ (double)outsetForLabel:(UIView *)label {
    UIWindow *window = label.window;
    if (!window) return 4.5;

    CGRect rect = [label convertRect:label.bounds toCoordinateSpace:window.screen.coordinateSpace];
    double outset = rect.origin.y - 2.0;
    if (outset < 1.5) outset = 1.5;
    if (outset > 4.5) outset = 4.5;
    return outset;
}

// The status bar reserves a fixed slot; the pill is allowed to borrow the date
// label's space when the date is hidden.
+ (UIEdgeInsets)paddingForLabel:(UIView *)label {
    UIEdgeInsets padding = [self padding];
    NSDate *date = [self visibleDateOfLabel:label];
    if (date) {
        UIView *companion = [self ownerOfLabel:label];
        if (companion) {
            CGRect rect = [companion convertRect:companion.bounds toView:label];
            padding.left += MAX(0.0, -CGRectGetMinX(rect));
        }
    }
    return padding;
}

#pragma mark - Companion label

+ (void)setCompanion:(UIView *)companion forLabel:(UIView *)label {
    if (companion && label) {
        [GLTCompanions() setObject:companion forKey:label];
    }
}

+ (UIView *)ownerOfLabel:(UIView *)label {
    return [GLTCompanions() objectForKey:label];
}

// Non-nil while the label owns a companion (date) label that is currently on
// screen. The status bar never tells us the date it is showing, so the return
// value is only used as a visibility sentinel by paddingForLabel: — this
// mirrors the original, which also returns a bare [NSDate date].
+ (NSDate *)visibleDateOfLabel:(UIView *)label {
    if (!label.window || label.isHidden || label.alpha < 0.5) return nil;
    if (CGRectIsEmpty(label.bounds)) return nil;

    UIView *companion = [self ownerOfLabel:label];
    if (!companion || companion.hidden || companion.alpha < 0.5) return nil;

    CGRect rect = [companion convertRect:companion.bounds toView:label];
    if (CGRectGetHeight(rect) <= 0) return nil;

    return [NSDate date];
}

// Remembers what the system wanted the label to say, so restoreAllLabels can
// put it back after the user turns Glint off.
+ (void)setSystemText:(NSString *)text forLabel:(UIView *)label {
    objc_setAssociatedObject(label, &kGLTSystemTextKey, text, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

#pragma mark - Background view

+ (UIView *)backgroundForLabel:(UIView *)label create:(BOOL)create {
    UIView *background = objc_getAssociatedObject(label, &kGLTBackgroundKey);
    if (background || !create) return background;

    background = [UIView new];
    background.userInteractionEnabled = NO;
    background.clipsToBounds = YES;
    background.layer.cornerCurve = kCACornerCurveContinuous;

    objc_setAssociatedObject(label, &kGLTBackgroundKey, background, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [GLTStyledLabels() addObject:background];
    return background;
}

+ (void)layoutBackgroundOfLabel:(UIView *)label {
    UIView *background = [self backgroundForLabel:label create:NO];
    if (!background) return;

    BOOL styled = [self isStyled:label];

    if (!styled) {
        [background removeFromSuperview];
        return;
    }

    UIView *host = label.superview;
    if (!host) return;

    // Keep the background directly underneath the label in the host's stack.
    NSArray *siblings = host.subviews;
    if ([siblings indexOfObject:background] == NSNotFound) {
        [host insertSubview:background belowSubview:label];
    }

    double outset = [self outsetForLabel:label];
    CGRect frame = [label convertRect:label.bounds toView:host];
    frame = CGRectInset(frame, -outset, -outset);
    if (CGRectIsEmpty(frame)) {
        background.hidden = YES;
        return;
    }

    background.hidden = label.hidden || label.alpha < 0.01;
    background.bounds = CGRectMake(0, 0, CGRectGetWidth(frame), CGRectGetHeight(frame));
    background.center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    background.transform = CGAffineTransformIdentity;
    background.layer.cornerRadius = CGRectGetHeight(frame) * 0.5;
}

#pragma mark - Applying content

+ (void)apply:(GLTPillContent *)content
      toLabel:(UILabel *)label
   background:(UIColor *)background
    textColor:(UIColor *)textColor
{
    [self apply:content toLabel:label background:background textColor:textColor animated:NO];
}

+ (void)apply:(GLTPillContent *)content
      toLabel:(UILabel *)label
   background:(UIColor *)background
    textColor:(UIColor *)textColor
     animated:(BOOL)animated
{
    BOOL styled = [self isStyled:label];
    if (!content && !styled) return;

    if (content) {
        BOOL fadeIn = animated && styled;

        _rendering = YES;
        if (!styled) {
            [self setSystemText:label.text forLabel:label];
            [self setSystemTextColor:label.textColor forLabel:label];
        }
        [GLTStyledLabels() addObject:label];
        objc_setAssociatedObject(label, &kGLTStyledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        textColor = [self foregroundColorForLabel:label];
        NSAttributedString *string = [content attributedStringWithFont:label.font color:textColor];
        if (![label.attributedText isEqualToAttributedString:string]) {
            label.attributedText = string;
        }
        label.textColor = textColor;

        UIView *back = [self backgroundForLabel:label create:YES];
        back.backgroundColor = background;

        _rendering = NO;

        [label invalidateIntrinsicContentSize];
        [label.superview setNeedsLayout];
        [label setNeedsLayout];
        [self layoutBackgroundOfLabel:label];

        if (fadeIn) {
            [self fadeInLabel:label];
        }
        return;
    }

    // Restore the untouched status bar.
    _rendering = YES;
    objc_setAssociatedObject(label, &kGLTStyledKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIView *back = [self backgroundForLabel:label create:NO];
    [back removeFromSuperview];
    objc_setAssociatedObject(label, &kGLTBackgroundKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    label.text = objc_getAssociatedObject(label, &kGLTSystemTextKey);
    UIColor *systemColor = [self systemTextColorForLabel:label];
    if (systemColor) label.textColor = systemColor;
    objc_setAssociatedObject(label, &kGLTSystemTextColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    _rendering = NO;

    [label invalidateIntrinsicContentSize];
    [label.superview setNeedsLayout];
    [label setNeedsLayout];
    [self layoutBackgroundOfLabel:label];
}

// Restores every label Glint has touched. Called when the tweak is disabled.
+ (void)restoreAllLabels {
    for (UILabel *label in [GLTStyledLabels() allObjects]) {
        [self apply:nil toLabel:label background:nil textColor:nil];
    }
    [GLTStyledLabels() removeAllObjects];
}

#pragma mark - Animation

// Snapshot of the outgoing content, scaling down and drifting up while it
// fades — the cross-fade used when the pill switches to another kind.
+ (void)fadeOutSnapshotOfLabel:(UIView *)label {
    UIView *snapshot = [label snapshotViewAfterScreenUpdates:NO];
    if (!snapshot) return;

    snapshot.userInteractionEnabled = NO;
    CGPoint center = label.center;
    CGRect bounds = label.bounds;
    snapshot.bounds = bounds;
    snapshot.center = center;
    snapshot.transform = label.transform;
    [label.superview insertSubview:snapshot aboveSubview:label];

    [UIView animateWithDuration:0.18
                          delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        snapshot.alpha = 0;
        CGAffineTransform transform = CGAffineTransformMakeScale(0.92, 0.92);
        snapshot.transform = CGAffineTransformTranslate(transform, 0, -6);
    } completion:^(BOOL finished) {
        [snapshot removeFromSuperview];
    }];
}

// Entry animation: opacity fades in first, then the content springs into place
// (scale 0.9 -> 1 and a 6pt rise) with damping 14 / stiffness 220 / mass 1.
+ (void)fadeInLabel:(UIView *)label {
    CFTimeInterval now = CACurrentMediaTime();

    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @0;
    fade.toValue = @1;
    fade.duration = 0.24;
    fade.beginTime = now + 0.1;
    fade.fillMode = kCAFillModeBackwards;
    fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [label.layer addAnimation:fade forKey:@"glint.fade"];

    CASpringAnimation *scale = [CASpringAnimation animationWithKeyPath:@"transform.scale"];
    scale.fromValue = @0.9;
    scale.toValue = @1;
    scale.damping = 14;
    scale.stiffness = 220;
    scale.mass = 1;
    scale.beginTime = now + 0.1;
    scale.fillMode = kCAFillModeBackwards;
    scale.duration = scale.settlingDuration;
    [label.layer addAnimation:scale forKey:@"glint.grow"];

    CASpringAnimation *rise = [CASpringAnimation animationWithKeyPath:@"transform.translation.y"];
    rise.fromValue = @6;
    rise.toValue = @0;
    rise.damping = scale.damping;
    rise.stiffness = scale.stiffness;
    rise.beginTime = now + 0.1;
    rise.fillMode = kCAFillModeBackwards;
    rise.duration = rise.settlingDuration;
    [label.layer addAnimation:rise forKey:@"glint.rise"];
}

// Tap feedback: a quick squash-and-settle on the label itself.
+ (void)popLabel:(UIView *)label {
    label.transform = CGAffineTransformMakeScale(0.94, 0.94);
    [UIView animateWithDuration:0.4
                          delay:0
         usingSpringWithDamping:0.55
          initialSpringVelocity:0.5
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        label.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        [self layoutBackgroundOfLabel:label];
    }];
    [self layoutBackgroundOfLabel:label];
}

@end
