//
//  GLTPlatterView.m
//  GLTPlatterContent + GLTPlatterView
//
//  The card shell: a blurred rounded container that sizes itself to whatever
//  content view it is given. Content subclasses only describe their rows.
//
//  Recovered from 0xdc6c…0xdf58 (content) and 0x14f10…0x15248 (shell).
//

#import "Glint.h"
#import <math.h>

static const CGFloat kGLTPlatterPadding = 20;

@implementation GLTPlatterContent

// Rows are stacked edge to edge and the stack is pinned to all four sides, so
// the shell can derive its height from Auto Layout.
- (void)fillWith:(NSArray<UIView *> *)rows {
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:rows];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    ]];
}

- (void)close {
    if (self.closeHandler) self.closeHandler();
}

- (BOOL)wantsKeyboard {
    return NO;
}

@end

@implementation GLTPlatterView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.clipsToBounds = YES;
    self.layer.cornerCurve = kCACornerCurveContinuous;

    _blurView = [[UIVisualEffectView alloc] initWithEffect:
                 [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark]];
    _blurView.contentView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    _blurView.clipsToBounds = YES;
    [self addSubview:_blurView];

    return self;
}

- (void)setContent:(GLTPlatterContent *)content {
    [_content removeFromSuperview];
    _content = content;
    if (!content) return;

    [self addSubview:content];
    [self setNeedsLayout];
}

// Measure at the requested width, including the status-bar inset and bottom padding.
- (double)heightForWidth:(double)width {
    CGSize fitted = [_content systemLayoutSizeFittingSize:CGSizeMake(width - kGLTPlatterPadding * 2,
                                                                     UILayoutFittingCompressedSize.height)
                          withHorizontalFittingPriority:UILayoutPriorityRequired
                                verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    return ceil(fitted.height + self.topInset + kGLTPlatterPadding);
}

- (void)layoutSubviews {
    [super layoutSubviews];

    _blurView.frame = self.bounds;

    // Keep the content measured at its open width while the shell animates.
    _content.frame = CGRectMake(kGLTPlatterPadding,
                                self.topInset,
                                self.openWidth - kGLTPlatterPadding * 2,
                                [self heightForWidth:self.openWidth] - self.topInset - kGLTPlatterPadding);
}

@end
