"""Object-returning clock Hook contract; Apple host replay is not device proof."""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(os.environ.get("GLINT_SOURCE_ROOT", Path(__file__).resolve().parents[1]))
SOURCE = ROOT / "reconstructed"


def extract_hook(text):
    hooks = re.findall(r"^static (?:void|id) glt_applyUpdate\([^\n]+\) \{\n.*?^\}", text, re.M | re.S)
    gates = re.findall(
        r'GLTMethodMatches\(timeItem, @selector\(applyUpdate:toDisplayItem:\), '
        r'@encode\((?:void|id)\), @\[@"@", @"@"\]\)', text,
    )
    if len(hooks) != 1 or len(gates) != 1:
        raise AssertionError("expected one production applyUpdate Hook and admission predicate")
    return hooks[0], gates[0]


HOST = r'''
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "GLTRuntime.h"
#include <stdio.h>
#include <stdlib.h>

// Only UIKit labels and the controller consumer are doubles; the extracted
// production Hook, its admission predicate and GLTMethodMatches run unchanged.
@interface UIView : NSObject @end
@implementation UIView @end
@protocol GLTStatusBarTimeItem
- (UIView *)timeView;
- (UIView *)dateView;
- (UIView *)shortTimeView;
@end

static id expectedReceiver, expectedUpdate, expectedDisplay, predecessorResult;
static UIView *expectedTime, *expectedDate, *expectedShort;
static NSMutableArray<NSString *> *events;
static NSUInteger originalCalls, registrations;
static IMP glt_orig_applyUpdate;

static void Require(BOOL condition, const char *message) {
    if (!condition) {
        fprintf(stderr, "GLINT_STATUSBAR_HOOK_HOST_FAIL: %s\n", message);
        exit(1);
    }
}

@interface GLTController : NSObject
+ (instancetype)sharedController;
- (void)registerClockView:(UIView *)view dateView:(UIView *)date;
@end
@implementation GLTController
+ (instancetype)sharedController {
    static GLTController *controller;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controller = [GLTController new]; });
    return controller;
}
- (void)registerClockView:(UIView *)view dateView:(UIView *)date {
    Require(originalCalls == 1, "original must run before registration");
    Require(registrations < 2, "exactly two registrations");
    Require(view == (registrations == 0 ? expectedTime : expectedShort), "registered clock identity");
    Require(date == (registrations == 0 ? expectedDate : nil), "registered date identity");
    [events addObject:registrations == 0 ? @"wide" : @"short"];
    registrations++;
}
@end

@interface GLTObjectTimeItem : NSObject <GLTStatusBarTimeItem>
- (id)applyUpdate:(id)update toDisplayItem:(id)display;
@end
@implementation GLTObjectTimeItem
- (UIView *)timeView { return expectedTime; }
- (UIView *)dateView { return expectedDate; }
- (UIView *)shortTimeView { return expectedShort; }
- (id)applyUpdate:(id)update toDisplayItem:(id)display {
    Require(self == expectedReceiver, "predecessor receiver identity");
    Require(sel_isEqual(_cmd, @selector(applyUpdate:toDisplayItem:)), "predecessor selector identity");
    Require(update == expectedUpdate && display == expectedDisplay, "predecessor explicit argument identity");
    originalCalls++;
    [events addObject:@"original"];
    return predecessorResult;
}
@end

@interface GLTVoidTimeItem : NSObject
- (void)applyUpdate:(id)update toDisplayItem:(id)display;
@end
@implementation GLTVoidTimeItem
- (void)applyUpdate:(id)update toDisplayItem:(id)display { (void)update; (void)display; }
@end

/* GLINT_PRODUCTION_APPLY_UPDATE */

static BOOL Admit(Class timeItem) {
    return /* GLINT_PRODUCTION_TIME_ITEM_ADMISSION */;
}

static void Exercise(id returned, BOOL nilViews, BOOL nilArguments) {
    GLTObjectTimeItem *item = [GLTObjectTimeItem new];
    expectedReceiver = item;
    expectedUpdate = nilArguments ? nil : [NSObject new];
    expectedDisplay = nilArguments ? nil : [NSObject new];
    predecessorResult = returned;
    expectedTime = nilViews ? nil : [UIView new];
    expectedDate = nilViews ? nil : [UIView new];
    expectedShort = nilViews ? nil : [UIView new];
    events = [NSMutableArray array];
    originalCalls = registrations = 0;
    SEL selector = @selector(applyUpdate:toDisplayItem:);
    glt_orig_applyUpdate = class_getMethodImplementation([item class], selector);
    // The cast also lets the frozen void baseline compile for admission RED.
    // A rejected baseline exits in main before this call can be reached.
    id (*replacement)(id, SEL, id, id) = (id (*)(id, SEL, id, id))glt_applyUpdate;
    id result = replacement(item, selector, expectedUpdate, expectedDisplay);
    Require(result == returned, "predecessor return identity");
    Require(originalCalls == 1 && registrations == 2, "exact call counts");
    Require([events isEqualToArray:@[@"original", @"wide", @"short"]], "original then label registration order");
}

int main(void) {
    @autoreleasepool {
        Require(Admit([GLTObjectTimeItem class]), "object-returning time-item admission");
        Require(!Admit([GLTVoidTimeItem class]), "incompatible void method rejected");
        Require(!Admit([NSObject class]) && !Admit(Nil), "missing method and class rejected");
        Exercise([NSObject new], NO, NO);
        Exercise(nil, NO, YES);
        Exercise([NSObject new], YES, NO);
        puts("GLINT_STATUSBAR_HOOK_HOST_PASS");
    }
    return 0;
}
'''


def host_source(hook, gate):
    text = HOST
    for marker, replacement in (
        ("/* GLINT_PRODUCTION_APPLY_UPDATE */", hook),
        ("/* GLINT_PRODUCTION_TIME_ITEM_ADMISSION */", gate),
    ):
        if text.count(marker) != 1:
            raise AssertionError("host extraction marker must be unique")
        text = text.replace(marker, replacement)
    return text


class StatusBarHookTests(unittest.TestCase):
    def test_apply_update_preserves_the_object_return_contract(self):
        hook, gate = extract_hook((SOURCE / "Tweak.xm").read_text())
        self.assertTrue(hook.startswith("static id glt_applyUpdate("), "original Hook returns an object, not void")
        self.assertIn("((id (*)(id, SEL, id, id))glt_orig_applyUpdate)", hook)
        self.assertEqual(hook.count("glt_orig_applyUpdate"), 1, "predecessor must run exactly once")
        saved = re.search(r"\bid (\w+) = \(\(id \(\*\)\(id, SEL, id, id\)\)glt_orig_applyUpdate\)", hook)
        self.assertIsNotNone(saved, "save the predecessor object before registering labels")
        assert saved is not None
        self.assertTrue(hook.endswith("    return " + saved[1] + ";\n}"))
        self.assertEqual(gate, 'GLTMethodMatches(timeItem, @selector(applyUpdate:toDisplayItem:), @encode(id), @[@"@", @"@"])')

    @unittest.skipUnless(sys.platform == "darwin", "requires Apple Foundation host; not an iOS/device test")
    def test_actual_hook_and_admission_with_negative_controls(self):
        hook, gate = extract_hook((SOURCE / "Tweak.xm").read_text())
        with tempfile.TemporaryDirectory(prefix="glint-statusbar-", dir=os.environ.get("TMPDIR")) as work:
            work = Path(work)

            def replay(name, body, predicate):
                source = work / (name + ".m")
                binary = work / name
                source.write_text(host_source(body, predicate))
                command = [
                    "xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror",
                    "-framework", "Foundation", "-I" + str(SOURCE / "Headers"),
                    str(SOURCE / "Sources/GLTRuntime.m"), str(source), "-o", str(binary),
                ]
                compiled = subprocess.run(command, capture_output=True, text=True, timeout=60)
                self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
                return subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)

            bad_gate = gate.replace("@encode(id)", "@encode(void)")
            self.assertNotEqual(bad_gate, gate)
            rejected = replay("wrong-gate", hook, bad_gate)
            self.assertEqual(rejected.returncode, 1, rejected.stdout + rejected.stderr)
            self.assertIn("GLINT_STATUSBAR_HOOK_HOST_FAIL: object-returning time-item admission", rejected.stderr)
            saved = re.search(r"\bid (\w+) = \(\(id \(\*\)\(id, SEL, id, id\)\)glt_orig_applyUpdate\)", hook)
            self.assertIsNotNone(saved)
            assert saved is not None
            bad_return = hook.replace("return " + saved[1] + ";", "(void)" + saved[1] + ";\n    return nil;")
            self.assertNotEqual(bad_return, hook)
            rejected = replay("dropped-return", bad_return, gate)
            self.assertEqual(rejected.returncode, 1, rejected.stdout + rejected.stderr)
            self.assertIn("GLINT_STATUSBAR_HOOK_HOST_FAIL: predecessor return identity", rejected.stderr)
            accepted = replay("production", hook, gate)
            self.assertEqual(accepted.returncode, 0, accepted.stdout + accepted.stderr)
            self.assertEqual(accepted.stdout.strip(), "GLINT_STATUSBAR_HOOK_HOST_PASS")
            print(accepted.stdout.strip(), flush=True)


if __name__ == "__main__":
    unittest.main()
