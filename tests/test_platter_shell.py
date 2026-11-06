"""Original-backed shell contracts; host doubles are not UIKit/device proof.

Reference: retained Glint.dylib arm64 SHA-256
 a4f0aabf448ebc50ddfaf8a2e08dcd2262ae494e01ff0756e9ab64bfa0ddc3bb.
-initWithFrame: 0x14f10: style 19; colorWithWhite:0 alpha:0.3 sent to
 blur.contentView. -heightForWidth: 0x150bc: W-40, priorities 1000/50,
 ceil(fitted.height + topInset + 20), with no nil-content early return.
-layoutSubviews 0x15134: blur=bounds; content=(20, topInset, openWidth-40,
 heightForWidth(openWidth)-topInset-20), independent of animated bounds width.
"""
from pathlib import Path
import hashlib
import os
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(os.environ.get("GLINT_SOURCE_ROOT", Path(__file__).resolve().parents[1]))
PLATTER = ROOT / "reconstructed/Sources/GLTPlatterView.m"
SIGNATURES = {
    "init": "- (instancetype)initWithFrame:(CGRect)frame",
    "height": "- (double)heightForWidth:(double)width",
    "layout": "- (void)layoutSubviews",
    "set_content": "- (void)setContent:(GLTPlatterContent *)content",
}


def extract_shell(text):
    """Inject exact production statements, never a rewritten geometry formula."""
    classes = re.findall(r"^@implementation GLTPlatterView\s*$", text, re.M)
    shells = re.findall(r"^@implementation GLTPlatterView\s*\n(.*?)^@end\s*$", text, re.M | re.S)
    padding = re.findall(r"^static const CGFloat kGLTPlatterPadding = [^;\n]+;$", text, re.M)
    if len(classes) != 1 or len(shells) != 1 or len(padding) != 1:
        raise AssertionError("expected one shell implementation and padding constant")
    methods = {"padding": padding[0]}
    for name, signature in SIGNATURES.items():
        anchors = re.findall(r"^" + re.escape(signature) + r"\s*\{", shells[0], re.M)
        bodies = re.findall(r"^" + re.escape(signature) + r"\s*\{\n.*?^\}", shells[0], re.M | re.S)
        if len(anchors) != 1 or len(bodies) != 1:
            raise AssertionError("expected one production " + name + " method")
        methods[name] = bodies[0]
    return methods


def compact(text):
    return re.sub(r"\s+", "", re.sub(r"//[^\n]*|/\*.*?\*/", "", text, flags=re.S))


HOST = r'''
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <math.h>
#include <stdio.h>
#include <stdlib.h>

// Foundation, ARC and CoreGraphics are real. UIKit's view/effect/layout
// participants are recording doubles; production methods below are unchanged.
static void Require(BOOL condition, const char *message) {
    if (!condition) {
        fprintf(stderr, "GLINT_PLATTER_SHELL_HOST_FAIL: %s\n", message);
        exit(1);
    }
}
static BOOL Near(double lhs, double rhs) { return fabs(lhs - rhs) < 0.000001; }
static BOOL SameRect(CGRect lhs, CGRect rhs) {
    return Near(lhs.origin.x, rhs.origin.x) && Near(lhs.origin.y, rhs.origin.y)
        && Near(lhs.size.width, rhs.size.width) && Near(lhs.size.height, rhs.size.height);
}

@interface UIColor : NSObject
@property(nonatomic) CGFloat white;
@property(nonatomic) CGFloat alpha;
+ (instancetype)colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha;
@end
@implementation UIColor
+ (instancetype)colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha {
    UIColor *color = [self new];
    color.white = white;
    color.alpha = alpha;
    return color;
}
@end

@interface GLTHostLayer : NSObject
@property(nonatomic, copy) NSString *cornerCurve;
@property(nonatomic) CGFloat cornerRadius;
@end
@implementation GLTHostLayer @end
static NSString *const kCACornerCurveContinuous = @"continuous";

@class UIView;
static __weak UIView *observedBlur, *observedContent;
static NSMutableArray<NSString *> *events;
static BOOL failNextViewInit;
static NSUInteger effectCalls;

@interface UIView : NSObject {
    NSMutableArray<UIView *> *_children;
}
@property(nonatomic) CGRect frame;
@property(nonatomic) CGRect bounds;
@property(nonatomic) BOOL clipsToBounds;
@property(nonatomic, strong) GLTHostLayer *layer;
@property(nonatomic, strong) UIColor *backgroundColor;
@property(nonatomic, weak) UIView *superview;
@property(nonatomic, readonly) NSArray<UIView *> *subviews;
- (instancetype)initWithFrame:(CGRect)frame;
- (void)addSubview:(UIView *)view;
- (void)removeFromSuperview;
- (void)setNeedsLayout;
- (void)layoutSubviews;
@end
@implementation UIView
@synthesize frame = _frame;
- (instancetype)init { return [self initWithFrame:CGRectZero]; }
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super init];
    if (failNextViewInit) { failNextViewInit = NO; return nil; }
    if (self) {
        _frame = frame;
        _bounds = CGRectMake(0, 0, frame.size.width, frame.size.height);
        _layer = [GLTHostLayer new];
        _children = [NSMutableArray array];
    }
    return self;
}
- (void)setFrame:(CGRect)frame {
    _frame = frame;
    if (self == observedBlur) [events addObject:@"blur-frame"];
    if (self == observedContent) [events addObject:@"content-frame"];
}
- (NSArray<UIView *> *)subviews { return [_children copy]; }
- (void)addSubview:(UIView *)view {
    [_children addObject:view];
    view.superview = self;
}
- (void)removeFromSuperview {
    [self.superview->_children removeObjectIdenticalTo:self];
    self.superview = nil;
}
- (void)setNeedsLayout {}
- (void)layoutSubviews { [events addObject:@"super-layout"]; }
@end

typedef NS_ENUM(NSInteger, UIBlurEffectStyle) {
    UIBlurEffectStyleSystemThinMaterialDark = 17,
    UIBlurEffectStyleSystemThickMaterialDark = 19,
};
@interface UIBlurEffect : NSObject
@property(nonatomic) UIBlurEffectStyle style;
+ (instancetype)effectWithStyle:(UIBlurEffectStyle)style;
@end
@implementation UIBlurEffect
+ (instancetype)effectWithStyle:(UIBlurEffectStyle)style {
    effectCalls++;
    UIBlurEffect *effect = [self new];
    effect.style = style;
    return effect;
}
@end

@interface UIVisualEffectView : UIView
@property(nonatomic, strong, readonly) UIView *contentView;
@property(nonatomic, strong, readonly) UIBlurEffect *effect;
- (instancetype)initWithEffect:(UIBlurEffect *)effect;
@end
@implementation UIVisualEffectView
- (instancetype)initWithEffect:(UIBlurEffect *)effect {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _effect = effect;
        _contentView = [UIView new];
        [self addSubview:_contentView];
    }
    return self;
}
@end

static const CGSize UILayoutFittingCompressedSize = {0, 0};
enum { UILayoutPriorityRequired = 1000, UILayoutPriorityFittingSizeLevel = 50 };
@interface GLTPlatterContent : UIView
@property(nonatomic) CGSize fittedSize;
@property(nonatomic) CGSize lastTarget;
@property(nonatomic) float lastHorizontal;
@property(nonatomic) float lastVertical;
@property(nonatomic) NSUInteger fittingCalls;
- (CGSize)systemLayoutSizeFittingSize:(CGSize)target
      withHorizontalFittingPriority:(float)horizontal verticalFittingPriority:(float)vertical;
@end
@implementation GLTPlatterContent
- (CGSize)systemLayoutSizeFittingSize:(CGSize)target
      withHorizontalFittingPriority:(float)horizontal verticalFittingPriority:(float)vertical {
    self.fittingCalls++;
    self.lastTarget = target;
    self.lastHorizontal = horizontal;
    self.lastVertical = vertical;
    [events addObject:@"fit"];
    return self.fittedSize;
}
@end

/* GLINT_PRODUCTION_PADDING */
@interface GLTPlatterView : UIView {
    UIVisualEffectView *_blurView;
    GLTPlatterContent *_content;
}
@property(nonatomic, strong) GLTPlatterContent *content;
@property(nonatomic) double topInset;
@property(nonatomic) double openWidth;
- (double)heightForWidth:(double)width;
- (UIVisualEffectView *)hostBlur;
@end
@implementation GLTPlatterView
@synthesize content = _content;
/* GLINT_PRODUCTION_INIT */
/* GLINT_PRODUCTION_SET_CONTENT */
/* GLINT_PRODUCTION_HEIGHT */
/* GLINT_PRODUCTION_LAYOUT */
- (UIVisualEffectView *)hostBlur { return _blurView; }
@end

@interface GLTHostObservedPlatter : GLTPlatterView
@property(nonatomic) NSUInteger heightCalls;
@property(nonatomic) double requestedWidth;
@end
@implementation GLTHostObservedPlatter
- (double)heightForWidth:(double)width {
    self.heightCalls++;
    self.requestedWidth = width;
    return [super heightForWidth:width];
}
@end

static void CheckFit(GLTPlatterContent *content, double targetWidth) {
    Require(content.fittingCalls == 1, "one fitting call");
    Require(Near(content.lastTarget.width, targetWidth) && Near(content.lastTarget.height, 0),
            "fit target width and compressed height");
    Require(Near(content.lastHorizontal, 1000) && Near(content.lastVertical, 50),
            "required horizontal and fitting-level vertical priorities");
}

static void Exercise(void) {
    GLTHostObservedPlatter *shell;
    __weak UIColor *retainedTint;
    @autoreleasepool {
        shell = [[GLTHostObservedPlatter alloc] initWithFrame:CGRectMake(8, 9, 390, 250)];
        retainedTint = shell.hostBlur.contentView.backgroundColor;
    }
    UIVisualEffectView *blur = shell.hostBlur;
    Require(shell != nil && effectCalls == 1, "one effect created after successful superclass init");
    Require(blur.effect.style == 19, "thick dark material");
    Require(blur.backgroundColor == nil && shell.backgroundColor == nil
            && retainedTint != nil && retainedTint == blur.contentView.backgroundColor
            && Near(retainedTint.white, 0) && Near(retainedTint.alpha, 0.3),
            "black 0.3 tint retained on blur contentView only");
    Require(shell.clipsToBounds && [shell.layer.cornerCurve isEqualToString:kCACornerCurveContinuous],
            "shell clipping and continuous curve");
    Require(shell.subviews.count == 1 && shell.subviews[0] == blur, "blur attached to shell");
    failNextViewInit = YES;
    Require([[GLTPlatterView alloc] initWithFrame:CGRectZero] == nil && effectCalls == 1,
            "failed superclass init returns nil without creating effect");

    GLTPlatterContent *content = [GLTPlatterContent new];
    shell.content = content; // Unchanged production setter, not a test-only attachment.
    observedBlur = blur;
    observedContent = content;
    Require(shell.subviews.count == 2 && shell.subviews[1] == content && content.superview == shell,
            "content attached after blur");
    // Precomputed expected values are independent fixtures, not a reimplementation
    // of production arithmetic. Returned fitting width deliberately differs.
    const struct {
        double width, inset, fittedWidth, fittedHeight, targetWidth, totalHeight, contentHeight;
    } cases[] = {
        {390, 0, 71, 79.2, 350, 100, 80},
        {390, 47.5, 321, 79.2, 350, 147, 79.5},
        {320, -3.25, 101, 0.125, 280, 17, 0.25},
        {40, 10.25, 0, 12.5, 0, 43, 12.75},
        {10, 2.125, 0, 0, -30, 23, 0.875},
        {0, -0.5, 0, 0, -40, 20, 0.5},
    };
    const double animatedWidths[] = {390, 110, 18};
    for (NSUInteger i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        shell.topInset = cases[i].inset;
        shell.openWidth = 999; // Direct height queries must use their argument.
        content.fittedSize = CGSizeMake(cases[i].fittedWidth, cases[i].fittedHeight);
        content.fittingCalls = 0;
        Require(Near([shell heightForWidth:cases[i].width], cases[i].totalHeight),
                "ceil includes top inset and bottom padding");
        CheckFit(content, cases[i].targetWidth);
        shell.openWidth = cases[i].width;
        for (NSUInteger j = 0; j < sizeof(animatedWidths) / sizeof(animatedWidths[0]); j++) {
            shell.bounds = CGRectMake(3, 7, animatedWidths[j], 2.25);
            shell.heightCalls = 0;
            content.fittingCalls = 0;
            events = [NSMutableArray array];
            [shell layoutSubviews];
            Require(shell.heightCalls == 1 && Near(shell.requestedWidth, cases[i].width),
                    "layout measures at openWidth exactly once");
            CheckFit(content, cases[i].targetWidth);
            Require(SameRect(blur.frame, shell.bounds), "blur follows animated bounds");
            Require(SameRect(content.frame, CGRectMake(20, cases[i].inset,
                                                      cases[i].targetWidth, cases[i].contentHeight)),
                    "layout content openWidth geometry");
            Require([events isEqualToArray:@[@"super-layout", @"blur-frame", @"fit", @"content-frame"]],
                    "super then blur frame then fitting then content frame");
        }
    }
    GLTPlatterContent *replacement = [GLTPlatterContent new];
    shell.content = replacement;
    Require(content.superview == nil && shell.subviews.count == 2 && replacement.superview == shell,
            "unchanged setter replaces content");
    shell.content = nil;
    Require(replacement.superview == nil && shell.subviews.count == 1, "unchanged setter clears content");
    shell.topInset = 0;
    Require(Near([shell heightForWidth:390], 20), "nil content height includes inset and bottom padding");
    shell.topInset = 47.5;
    Require(Near([shell heightForWidth:390], 68), "nil content height includes inset and bottom padding");
    shell.topInset = -3.25;
    Require(Near([shell heightForWidth:390], 17), "nil content height includes inset and bottom padding");
    shell.bounds = CGRectMake(3, 7, 18, 2);
    [shell layoutSubviews];
    Require(SameRect(blur.frame, shell.bounds), "nil content still lays out blur");
}

int main(void) {
    @autoreleasepool {
        Exercise();
        puts("GLINT_PLATTER_SHELL_HOST_PASS");
    }
    return 0;
}
'''


def host_source(methods, template=HOST):
    for key in ("padding", "init", "set_content", "height", "layout"):
        marker = "/* GLINT_PRODUCTION_" + key.upper() + " */"
        if template.count(marker) != 1:
            raise AssertionError("host extraction marker must be unique: " + key)
        template = template.replace(marker, methods[key])
    return template


def mutated_methods(methods):
    controls = (
        ("wrong-material", "init", "UIBlurEffectStyleSystemThickMaterialDark",
         "UIBlurEffectStyleSystemThinMaterialDark", "thick dark material"),
        ("wrong-tint-layer", "init", "_blurView.contentView.backgroundColor",
         "_blurView.backgroundColor", "black 0.3 tint retained on blur contentView only"),
        ("wrong-ceil", "height", "ceil(", "floor(", "ceil includes top inset and bottom padding"),
        ("wrong-layout-width", "layout", "self.openWidth - kGLTPlatterPadding * 2",
         "CGRectGetWidth(self.bounds) - kGLTPlatterPadding * 2", "layout content openWidth geometry"),
        ("wrong-measure-width", "layout", "[self heightForWidth:self.openWidth]",
         "[self heightForWidth:CGRectGetWidth(self.bounds)]", "layout measures at openWidth exactly once"),
        ("wrong-nil-height", "height", "{\n", "{\n    if (!_content) return 40;\n",
         "nil content height includes inset and bottom padding"),
        ("wrong-priority", "height", "withHorizontalFittingPriority:UILayoutPriorityRequired",
         "withHorizontalFittingPriority:UILayoutPriorityFittingSizeLevel",
         "required horizontal and fitting-level vertical priorities"),
    )
    for name, key, old, new, failure in controls:
        if methods[key].count(old) != 1:
            raise AssertionError("semantic mutation anchor must be unique: " + name)
        changed = dict(methods)
        changed[key] = changed[key].replace(old, new)
        yield name, changed, failure


class PlatterShellTests(unittest.TestCase):
    def test_shell_material_measurement_and_layout_match_original(self):
        methods = extract_shell(PLATTER.read_text())
        expected_height = """
- (double)heightForWidth:(double)width {
    CGSize fitted = [_content systemLayoutSizeFittingSize:CGSizeMake(width - kGLTPlatterPadding * 2,
                                                                     UILayoutFittingCompressedSize.height)
                          withHorizontalFittingPriority:UILayoutPriorityRequired
                                verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    return ceil(fitted.height + self.topInset + kGLTPlatterPadding);
}
"""
        expected_layout = """
- (void)layoutSubviews {
    [super layoutSubviews];
    _blurView.frame = self.bounds;
    _content.frame = CGRectMake(kGLTPlatterPadding,
                                self.topInset,
                                self.openWidth - kGLTPlatterPadding * 2,
                                [self heightForWidth:self.openWidth] - self.topInset - kGLTPlatterPadding);
}
"""
        actual = {
            "material": "UIBlurEffectStyleSystemThickMaterialDark" in methods["init"],
            "tint_layer": "_blurView.contentView.backgroundColor=[UIColorcolorWithWhite:0alpha:0.3];" in compact(methods["init"]),
            "no_preference_background": "GLTPrefs" not in "\n".join(methods.values()),
            "padding": compact(methods["padding"]),
            "height": compact(methods["height"]),
            "layout": compact(methods["layout"]),
        }
        expected = {
            "material": True,
            "tint_layer": True,
            "no_preference_background": True,
            "padding": "staticconstCGFloatkGLTPlatterPadding=20;",
            "height": compact(expected_height),
            "layout": compact(expected_layout),
        }
        self.assertEqual(actual, expected, "original shell material/topInset/openWidth contract")

    def test_content_and_setter_remain_byte_identical_to_baseline(self):
        text = PLATTER.read_bytes().decode("utf-8")
        contents = re.findall(r"^@implementation GLTPlatterContent\n.*?^@end", text, re.M | re.S)
        self.assertEqual(len(contents), 1)
        self.assertEqual(hashlib.sha256(contents[0].encode()).hexdigest(),
                         "a32a7e3c974b38cfaea0a26987c5b4b30694642bd03a9a9d59cbef404c3a3098")
        setter = extract_shell(text)["set_content"]
        self.assertEqual(hashlib.sha256(setter.encode()).hexdigest(),
                         "c36b41fbb419d13821ac15dd9f1ac7d0e29cb75e63a03d1ea5bfefaf3d18d4f2")

    def test_extraction_rejects_missing_or_duplicate_production_anchors(self):
        text = PLATTER.read_text()
        methods = extract_shell(text)
        for key, signature in SIGNATURES.items():
            with self.subTest(method=key, corruption="missing"):
                with self.assertRaisesRegex(AssertionError, "one production " + key):
                    extract_shell(text.replace(signature, signature + "Missing", 1))
            with self.subTest(method=key, corruption="duplicate"):
                with self.assertRaisesRegex(AssertionError, "one production " + key):
                    extract_shell(text.replace(methods[key], methods[key] + "\n" + methods[key], 1))
        for anchor in ("@implementation GLTPlatterView", methods["padding"]):
            for replacement in ("", anchor + "\n" + anchor):
                with self.subTest(anchor=anchor, replacement=replacement):
                    with self.assertRaisesRegex(AssertionError, "one shell implementation and padding"):
                        extract_shell(text.replace(anchor, replacement, 1))

    def test_host_injects_unchanged_production_methods_and_rejects_bad_markers(self):
        methods = extract_shell(PLATTER.read_text())
        generated = host_source(methods)
        for key, body in methods.items():
            with self.subTest(method=key):
                self.assertEqual(generated.count(body), 1)
                marker = "/* GLINT_PRODUCTION_" + key.upper() + " */"
                for replacement in ("", marker + marker):
                    with self.assertRaisesRegex(AssertionError, "marker must be unique"):
                        host_source(methods, HOST.replace(marker, replacement))
        controls = list(mutated_methods(methods))
        self.assertEqual(len(controls), 7)
        self.assertEqual(len({name for name, _, _ in controls}), 7)
        for name, changed, failure in controls:
            with self.subTest(control=name):
                self.assertEqual(sum(changed[key] != body for key, body in methods.items()), 1)
                self.assertIn('"' + failure + '"', HOST)
                self.assertNotEqual(host_source(changed), generated)

    @unittest.skipUnless(sys.platform == "darwin", "requires Apple Foundation/CoreGraphics host; not an iOS/device test")
    def test_actual_shell_methods_with_compiled_semantic_negative_controls(self):
        methods = extract_shell(PLATTER.read_text())
        with tempfile.TemporaryDirectory(prefix="glint-platter-", dir=os.environ.get("TMPDIR")) as work:
            work = Path(work)

            def replay(name, selected):
                source = work / (name + ".m")
                binary = work / name
                source.write_text(host_source(selected))
                command = [
                    "xcrun", "clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
                    "-framework", "Foundation", "-framework", "CoreGraphics",
                    str(source), "-o", str(binary),
                ]
                compiled = subprocess.run(command, capture_output=True, text=True, timeout=60)
                self.assertEqual(compiled.returncode, 0, " ".join(command) + "\n" + compiled.stdout + compiled.stderr)
                return subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)

            accepted = replay("production", methods)
            self.assertEqual(accepted.returncode, 0, accepted.stdout + accepted.stderr)
            self.assertEqual(accepted.stdout.strip(), "GLINT_PLATTER_SHELL_HOST_PASS")
            self.assertEqual(accepted.stderr, "")
            for name, changed, failure in mutated_methods(methods):
                with self.subTest(control=name):
                    rejected = replay(name, changed)
                    self.assertEqual(rejected.returncode, 1, rejected.stdout + rejected.stderr)
                    self.assertEqual(rejected.stderr.strip(), "GLINT_PLATTER_SHELL_HOST_FAIL: " + failure)
                    self.assertNotIn("GLINT_PLATTER_SHELL_HOST_PASS", rejected.stdout)
            print(accepted.stdout.strip(), flush=True)


if __name__ == "__main__":
    unittest.main()
