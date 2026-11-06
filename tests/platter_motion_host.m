// Foundation/CoreGraphics recording doubles, NOT UIKit or a handset renderer.
// Test driver inserts exact production methods/constants at the marked slots.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>

static void Require(BOOL ok, const char *message) {
    if (!ok) { fprintf(stderr, "GLINT_MOTION_HOST_FAIL: %s\n", message); exit(1); }
}
typedef NSUInteger UIViewAnimationOptions;
static const UIViewAnimationOptions UIViewAnimationOptionAllowUserInteraction = 1;
static const UIViewAnimationOptions UIViewAnimationOptionBeginFromCurrentState = 2;
static const NSUInteger UIControlEventTouchUpInside = 1;
static const NSInteger UIImpactFeedbackStyleLight = 0;
typedef struct { CGFloat top, left, bottom, right; } UIEdgeInsets;
static NSMutableArray *animations;
static NSMutableArray *completions;
static NSInteger activeAnimation = -1;
static BOOL synchronousCompletion;
// GLINT_PRODUCTION_CONSTANTS

@interface GLTLayer : NSObject
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic) NSInteger lastRadiusAnimation;
@end
@implementation GLTLayer
@synthesize cornerRadius = _cornerRadius;
- (void)setCornerRadius:(CGFloat)radius {
    _cornerRadius = radius;
    self.lastRadiusAnimation = activeAnimation;
}
@end
@interface UIColor : NSObject
+ (instancetype)colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha;
@end
@implementation UIColor
+ (instancetype)colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha { return [self new]; }
@end

@interface UIView : NSObject
@property CGRect frame;
@property(readonly) CGRect bounds;
@property(strong) GLTLayer *layer;
@property(strong) UIColor *backgroundColor;
@property CGFloat alpha;
@property CGAffineTransform transform;
@property BOOL userInteractionEnabled;
@property(weak) UIView *superview;
@property(strong) NSMutableArray *children;
@property NSUInteger layoutCount;
@property NSInteger lastLayoutAnimation;
@property CGFloat mountedRadius;
@property NSUInteger mountedLayouts;
- (instancetype)initWithFrame:(CGRect)frame;
- (void)addSubview:(UIView *)child;
- (void)removeFromSuperview;
- (void)setNeedsLayout;
- (void)layoutIfNeeded;
- (void)layoutSubviews;
+ (void)animateWithDuration:(NSTimeInterval)duration delay:(NSTimeInterval)delay
    usingSpringWithDamping:(CGFloat)damping initialSpringVelocity:(CGFloat)velocity
    options:(UIViewAnimationOptions)options animations:(void (^)(void))body
    completion:(void (^)(BOOL))completion;
+ (void)animateWithDuration:(NSTimeInterval)duration animations:(void (^)(void))body
    completion:(void (^)(BOOL))completion;
@end
@implementation UIView
- (instancetype)init { return [self initWithFrame:CGRectZero]; }
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super init])) {
        _frame = frame; _layer = [GLTLayer new]; _children = [NSMutableArray new];
        _alpha = 1; _transform = CGAffineTransformIdentity; _userInteractionEnabled = YES;
        _lastLayoutAnimation = -1;
    }
    return self;
}
- (CGRect)bounds { return CGRectMake(0, 0, _frame.size.width, _frame.size.height); }
- (void)addSubview:(UIView *)child {
    [child removeFromSuperview]; child.superview = self; [_children addObject:child];
    child.mountedRadius = child.layer.cornerRadius; child.mountedLayouts = child.layoutCount;
}
- (void)removeFromSuperview { [self.superview.children removeObjectIdenticalTo:self]; self.superview = nil; }
- (void)setNeedsLayout {}
- (void)layoutIfNeeded { self.layoutCount++; self.lastLayoutAnimation = activeAnimation; [self layoutSubviews]; }
- (void)layoutSubviews {}
+ (void)animateWithDuration:(NSTimeInterval)duration delay:(NSTimeInterval)delay
    usingSpringWithDamping:(CGFloat)damping initialSpringVelocity:(CGFloat)velocity
    options:(UIViewAnimationOptions)options animations:(void (^)(void))body
    completion:(void (^)(BOOL))completion {
    [animations addObject:@[@(duration), @(delay), @(damping), @(velocity), @(options)]];
    activeAnimation = animations.count - 1; body(); activeAnimation = -1;
    if (completion) {
        if (synchronousCompletion) completion(YES);
        else [completions addObject:[completion copy]];
    }
}
+ (void)animateWithDuration:(NSTimeInterval)duration animations:(void (^)(void))body
    completion:(void (^)(BOOL))completion {
    [self animateWithDuration:duration delay:0 usingSpringWithDamping:0
        initialSpringVelocity:0 options:0 animations:body completion:completion];
}
@end

@interface UIControl : UIView
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(NSUInteger)events;
@end
@implementation UIControl
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(NSUInteger)events {}
@end
@interface UIViewController : NSObject
@property(strong) UIView *view;
@end
@implementation UIViewController
@end
@interface UIWindow : UIView
@property(strong) UIViewController *rootViewController;
@property UIEdgeInsets safeAreaInsets;
@property BOOL acceptsKeyboard;
@property NSUInteger becameKey, madeKey, endedEditing;
- (void)becomeKeyWindow;
- (void)makeKeyWindow;
- (void)endEditing:(BOOL)force;
@end
@implementation UIWindow
- (void)becomeKeyWindow { self.becameKey++; }
- (void)makeKeyWindow { self.madeKey++; }
- (void)endEditing:(BOOL)force { self.endedEditing++; }
@end
@interface UIApplication : NSObject
@property(strong) UIWindow *keyWindow;
+ (instancetype)sharedApplication;
@end
@implementation UIApplication
+ (instancetype)sharedApplication { static UIApplication *app; if (!app) app = [self new]; return app; }
@end
@interface UIImpactFeedbackGenerator : NSObject
- (instancetype)initWithStyle:(NSInteger)style;
- (void)impactOccurred;
@end
@implementation UIImpactFeedbackGenerator
- (instancetype)initWithStyle:(NSInteger)style { return [super init]; }
- (void)impactOccurred {}
@end

@interface GLTPlatterContent : UIView
@property(copy) void (^closeHandler)(void);
@property(copy) void (^resizeHandler)(void);
@property BOOL keyboard;
@property CGFloat measuredHeight;
- (BOOL)wantsKeyboard;
@end
@implementation GLTPlatterContent
- (BOOL)wantsKeyboard { return self.keyboard; }
@end
@interface GLTPlatterView : UIView {
    GLTPlatterContent *_content;
    UIView *_blurView;
}
@property(nonatomic, strong) GLTPlatterContent *content;
@property CGFloat openWidth, topInset;
@property(readonly) CGRect blurFrame;
- (double)heightForWidth:(double)width;
@end
@implementation GLTPlatterView
@synthesize content = _content;
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) { _blurView = [UIView new]; [self addSubview:_blurView]; }
    return self;
}
- (void)setContent:(GLTPlatterContent *)content { [_content removeFromSuperview]; _content = content; [self addSubview:content]; }
- (double)heightForWidth:(double)width { return _content.measuredHeight + self.topInset + 20; }
- (CGRect)blurFrame { return _blurView.frame; }
// GLINT_PRODUCTION_LAYOUT
@end

@interface GLTController : NSObject {
@public
    UIWindow *_window;
    UIWindow *_previousKeyWindow;
    GLTPlatterView *_platterView;
    UIControl *_dismissView;
    CGRect _anchorFrame;
}
@property BOOL admitted;
@property NSUInteger touchLayouts;
- (BOOL)canPresentOverlay;
- (NSInteger)cutout;
- (void)layoutTouchView;
- (void)openPlatter:(GLTPlatterContent *)content;
- (void)closePlatter;
- (void)closePlatterAnimated:(BOOL)animated;
- (void)fitPlatterToContent;
@end
@implementation GLTController
- (BOOL)canPresentOverlay { return self.admitted; }
- (void)layoutTouchView { self.touchLayouts++; }
// GLINT_PRODUCTION_METHODS
@end

static void Drain(BOOL finished) {
    NSArray *pending = [completions copy]; [completions removeAllObjects];
    for (void (^completion)(BOOL) in pending) completion(finished);
}
static GLTController *Controller(CGFloat safeTop) {
    animations = [NSMutableArray new]; completions = [NSMutableArray new];
    GLTController *c = [GLTController new]; c.admitted = YES;
    c->_window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    c->_window.rootViewController = [UIViewController new];
    c->_window.rootViewController.view = [[UIView alloc] initWithFrame:c->_window.bounds];
    c->_window.safeAreaInsets = (UIEdgeInsets){safeTop, 0, 34, 0};
    c->_anchorFrame = CGRectMake(34, 12, 52, 22);
    return c;
}
static GLTPlatterContent *Content(void) {
    GLTPlatterContent *content = [GLTPlatterContent new]; content.measuredHeight = 190; return content;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        const char *mode = argc > 1 ? argv[1] : "lifecycle";
        if (!strcmp(mode, "rounding")) {
            for (NSUInteger i = 0; i < 3; i++) {
                GLTController *c = Controller(((CGFloat[]){59, 47, 20})[i]);
                [c openPlatter:Content()]; GLTPlatterView *p = c->_platterView;
                Require(p.mountedRadius == ((CGFloat[]){44, 36, 22})[i] && p.mountedLayouts > 0,
                        "rounded shell initialized before mount");
                Require(CGRectEqualToRect(p.blurFrame, p.bounds) && p.lastLayoutAnimation == 0,
                        "blur follows shell in opening animation");
                Require(animations.count == 2 && [animations[0][0] doubleValue] == 0.6 &&
                        [animations[0][2] doubleValue] == 0.72 && [animations[0][3] doubleValue] == 0.4,
                        "accepted opening spring");
            }
        } else if (!strcmp(mode, "compact-radius")) {
            for (NSUInteger i = 0; i < 3; i++) for (NSUInteger j = 0; j < 5; j++) {
                GLTController *c = Controller(((CGFloat[]){59,47,20})[i]);
                CGFloat height = ((CGFloat[]){16,22,26,34,38})[j];
                c->_anchorFrame.size.height = height;
                [c openPlatter:Content()]; GLTPlatterView *p = c->_platterView;
                [c closePlatterAnimated:YES];
                Require(p.layer.cornerRadius == height * 0.5, "compact radius follows pill height");
                Require(p.layer.lastRadiusAnimation == 2 && p.lastLayoutAnimation == 2,
                        "compact radius frame and blur share closing transaction");
                Drain(YES);
            }
        } else if (!strcmp(mode, "close")) {
            GLTController *c = Controller(59); [c openPlatter:Content()];
            GLTPlatterView *p = c->_platterView; CGRect target = c->_anchorFrame;
            [c closePlatterAnimated:YES];
            Require(CGRectEqualToRect(p.frame, target), "whole shell retracts to captured pill");
            Require(CGRectEqualToRect(p.blurFrame, p.bounds) && p.lastLayoutAnimation == 2,
                    "closing blur shares shell animation");
            Require([animations[2][0] doubleValue] == 0.6 && [animations[2][2] doubleValue] == 1 &&
                    [animations[2][3] doubleValue] == 0 && [animations[2][4] unsignedIntegerValue] == 3,
                    "critical interruptible closing spring");
            Require(p.alpha == 1 && p.content.alpha == 0 &&
                    CGAffineTransformEqualToTransform(p.content.transform,
                        CGAffineTransformScale(CGAffineTransformMakeTranslation(0, -14), 0.94, 0.94)),
                    "material opaque and content compact inverse");
            c->_anchorFrame = CGRectMake(90, 90, 90, 90);
            Require(CGRectEqualToRect(p.frame, target), "closing target captured before later clock layout");
            Drain(NO); Require(!p.superview, "interrupted close completion removes old shell");
        } else {
            GLTController *c = Controller(59);
            [c openPlatter:nil]; Require(!c->_platterView && !animations.count, "nil admission");
            c.admitted = NO; [c openPlatter:Content()]; Require(!c->_platterView, "overlay admission"); c.admitted = YES;
            GLTPlatterContent *oldContent = Content(); oldContent.keyboard = YES;
            UIWindow *previousKey = [UIWindow new]; [UIApplication sharedApplication].keyWindow = previousKey;
            [c openPlatter:oldContent]; GLTPlatterView *old = c->_platterView;
            [c openPlatter:Content()]; Require(c->_platterView == old && animations.count == 2, "one current shell");
            void (^staleClose)(void) = oldContent.closeHandler;
            void (^staleResize)(void) = oldContent.resizeHandler;
            // Exact Weather handler-copy assignments are inserted here.
            GLTPlatterContent *previous = oldContent;
            GLTPlatterContent *content = Content();
            // GLINT_PRODUCTION_WEATHER_COPY
            old.content = content;
            content.measuredHeight = 230; content.resizeHandler();
            Require(old.frame.size.height == 306, "replacement content retains same-shell resize authority");
            [c closePlatterAnimated:YES];
            Require(!old.userInteractionEnabled && !content.closeHandler && !content.resizeHandler,
                    "retiring shell deauthorized synchronously");
            Require(!c->_platterView && !c->_dismissView && !c->_window.acceptsKeyboard &&
                    c->_window.endedEditing == 1 && previousKey.madeKey == 1 && !c->_previousKeyWindow,
                    "keyboard and dismiss owners detach synchronously");
            [c openPlatter:Content()]; GLTPlatterView *current = c->_platterView;
            UIControl *dismiss = c->_dismissView; NSUInteger count = animations.count;
            current.content.measuredHeight = 400;
            staleResize(); staleClose();
            Require(c->_platterView == current && animations.count == count,
                    "retained old callbacks cannot mutate replacement shell");
            Drain(NO);
            Require(c->_platterView == current && c->_dismissView == dismiss && current.superview && !old.superview,
                    "old interrupted completion cannot clear replacement owners");
            current.content.closeHandler(); Require(!c->_platterView, "current callback retains authority"); Drain(YES);
            [c openPlatter:Content()]; GLTPlatterView *locked = c->_platterView; count = animations.count;
            [c closePlatterAnimated:NO];
            Require(!locked.superview && !c->_platterView && !c->_dismissView && animations.count == count,
                    "nonanimated lock close cleans immediately");
            [c closePlatterAnimated:NO]; Require(animations.count == count, "nil close is inert");
            // A synchronous receiver approximates disabled animation completion only;
            // it does not emulate Accessibility Reduce Motion or UIKit scheduling.
            synchronousCompletion = YES;
            [c openPlatter:Content()]; GLTPlatterView *instant = c->_platterView;
            [c closePlatterAnimated:YES]; Require(!instant.superview && !c->_platterView, "synchronous completion ownership");
        }
        puts("GLINT_MOTION_HOST_PASS");
    }
    return 0;
}
