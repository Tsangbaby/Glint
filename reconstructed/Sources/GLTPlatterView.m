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
                 [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
    _blurView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.25];
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

// Ask the content how tall it wants to be at the given width; the padding is
// the shell's contribution.
- (double)heightForWidth:(double)width {
    if (!_content) return kGLTPlatterPadding * 2;

    CGSize fitted = [_content systemLayoutSizeFittingSize:CGSizeMake(width - kGLTPlatterPadding * 2,
                                                                     UILayoutFittingCompressedSize.height)
                          withHorizontalFittingPriority:UILayoutPriorityRequired
                                verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    return fitted.height + kGLTPlatterPadding * 2;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    _blurView.frame = self.bounds;
    _blurView.layer.cornerRadius = self.layer.cornerRadius;

    // The card hangs below the status bar; topInset keeps the first row clear
    // of the notch.
    CGFloat top = _topInset > 0 ? 0 : kGLTPlatterPadding;
    CGRect bounds = self.bounds;
    _content.frame = CGRectMake(kGLTPlatterPadding,
                                top + kGLTPlatterPadding * 0,
                                CGRectGetWidth(bounds) - kGLTPlatterPadding * 2,
                                CGRectGetHeight(bounds) - kGLTPlatterPadding);
}

@end
