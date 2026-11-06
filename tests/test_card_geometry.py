"""Original-bound card source contracts and extracted numeric C replay.

The C replay executes the production arithmetic after explicit UIKit-input
substitution. It is not UIKit, an Objective-C runtime, or a handset test.
Original reference: Glint 1.6.3 arm64 SHA256
 a4f0aabf448ebc50ddfaf8a2e08dcd2262ae494e01ff0756e9ab64bfa0ddc3bb.
cutout 0x8f6c; openPlatter 0x9170 (clamps 0x9550..0x9580);
frame-writing animation 0x9810; resize admission 0x98cc; tap anchor 0x9d60.
Shell spring velocity: d3=0.4 at 0x9614, selector call at 0x9628.
"""
from pathlib import Path
import hashlib
import os
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(os.environ.get("GLINT_SOURCE_ROOT", Path(__file__).resolve().parents[1]))
SOURCE = ROOT / "reconstructed"
CONTROLLER = SOURCE / "Sources/GLTController.m"
# The new original-card/menu restoration explicitly widens only these bodies.
# The unchanged-zone digest below is derived from frozen predecessor
# 1bb2313d9b2e7e5e651f47b654419f26968c87be, NOT from the edited worktree.
APPROVED_METHODS = (
    "cutout", "openPlatter", "fitPlatterToContent", "clockTapped",
    "contentForPill", "storageContent", "weatherContent", "countContent", "sunContent",
    "platterContent", "pickerRowForPill", "pickerCellForPill", "showPicker",
    "pickerRowTapped", "hidePicker",
)


def method(text, name):
    pattern = r"^[+-] \([^\n)]+\)" + re.escape(name) + r"(?=\s|:)[^{;]*\{\n.*?^\}"
    matches = list(re.finditer(pattern, text, re.M | re.S))
    if len(matches) != 1:
        raise AssertionError("expected exactly one production method: " + name)
    return matches[0].group()


def unique(pattern, text):
    values = re.findall(pattern, text, re.M | re.S)
    if len(values) != 1:
        raise AssertionError("non-unique production arithmetic boundary: " + pattern)
    return values[0]


def spring_animations(body, source):
    """Extract each complete spring tuple, resolving production constants."""
    pattern = (
        r"\[UIView\s+animateWithDuration:\s*([^\n]+)\s+"
        r"delay:\s*([^\n]+)\s+"
        r"usingSpringWithDamping:\s*([^\n]+)\s+"
        r"initialSpringVelocity:\s*([^\n]+)\s+"
        r"options:\s*([^\n]+)\s+animations:\s*\^\{"
    )

    def number(expression):
        expression = expression.strip()
        if re.fullmatch(r"[A-Za-z_]\w*", expression):
            expression = unique(
                r"^static const [^\n]*\b" + re.escape(expression)
                + r"\s*=\s*([^;\n]+);$", source
            )
        return float(expression)

    return [
        tuple(number(value) for value in values[:4])
        + (" ".join(values[4].split()),)
        for values in re.findall(pattern, body)
    ]


def protected_controller(text):
    # These are the only approved bodies; shared Scene/touch/lifecycle code remains
    # byte-bound (with the baseline's existing CRLF normalized for this digest).
    for name in APPROVED_METHODS:
        body = method(text, name)
        text = text.replace(body, "/* APPROVED_CARD_METHOD:" + name + " */", 1)
    for name, allowed in (
        ("kGLTPlatterSpringDamping", {"0.78", "0.72"}),
        ("kGLTPlatterOpenDuration", {"0.42", "0.6"}),
        ("kGLTPlatterMinHeight", {"44"}),
    ):
        pattern = r"^static const [^\n]*\b" + name + r"\s*=\s*([^;\n]+);\n"
        values = re.findall(pattern, text, re.M)
        if len(values) > 1 or any(v.strip() not in allowed for v in values):
            raise AssertionError("unauthorized constant mutation: " + name)
        if name != "kGLTPlatterMinHeight" and len(values) != 1:
            raise AssertionError("missing retained card constant: " + name)
        text = re.sub(pattern, "", text, flags=re.M)
    return hashlib.sha256(text.encode()).hexdigest()


def protected_preferences(text):
    # Only presentation/cycle order and its original-provenance comment may
    # change. Persisted IDs, names/symbols, defaults and all readers stay frozen.
    start, end = "#pragma mark - Pill catalogue\n\n", "// Backed by the __const tables"
    if text.count(start) != 1 or text.count(end) != 1 or text.index(start) >= text.index(end):
        raise AssertionError("missing/duplicate/out-of-order pill-order boundaries")
    prefix, rest = text.split(start, 1)
    order, suffix = rest.split(end, 1)
    method(start + order, "pillOrder")
    return hashlib.sha256((prefix + start + "/* AUTHORIZED_PILL_ORDER */\n\n" + end + suffix).encode()).hexdigest()


C_PREFIX = r'''
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
typedef double CGFloat;
typedef long NSInteger;
typedef struct { CGFloat x, y; } CGPoint;
typedef struct { CGFloat width, height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;
static CGRect CGRectMake(CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    return (CGRect){{x,y},{w,h}};
}
static CGFloat CGRectGetMidX(CGRect r) { return r.origin.x + r.size.width * 0.5; }
#define MIN(a,b) ((a) < (b) ? (a) : (b))
#define MAX(a,b) ((a) > (b) ? (a) : (b))
static void Require(int ok, const char *reason) {
    if (!ok) { fprintf(stderr,"GLINT_CARD_GEOMETRY_FAIL: %s\n",reason); exit(1); }
}
'''


def cutout_c(text):
    body = method(text, "cutout")
    result_type = unique(r"^- \(([^)]+)\)cutout", body)
    body = body[body.index("{"):].replace("_window.safeAreaInsets.top", "safeTop")
    if "[" in body or "_window" in body:
        raise AssertionError("unexpected Objective-C dependency in cutout arithmetic")
    return "static " + result_type + " Cutout(CGFloat safeTop) " + body + "\n"


def placement_c(text):
    body = method(text, "openPlatter")
    width = unique(r"^    (CGFloat width = [^;]+;)$", body)
    center = unique(r"^    (CGFloat centerX = CGRectGetMidX\(anchor\);)$", body)
    # The rejected baseline remains executable by the same extractor; its
    # negative left edge must fail behavior, not parsing or compilation.
    if "CGRect openFrame =" in body:
        placement = unique(r"^    (CGFloat x = .*?CGRect openFrame = CGRectMake\([^;]+;)", body)
        placement = placement.replace("CGRect openFrame =", "return", 1)
    else:
        placement = "return " + unique(r"platter\.frame = (CGRectMake\([^;]+\));", body) + ";"
    actual = width + "\n" + center + "\n" + placement
    actual = actual.replace("CGRectGetWidth(host.bounds)", "hostWidth")
    if "[" in actual or "host." in actual:
        raise AssertionError("unhandled external placement dependency")
    return r'''static CGRect Place(CGFloat hostWidth, CGFloat screenWidth, CGRect anchor,
                                     CGFloat top, CGFloat height) {
    (void)hostWidth; (void)screenWidth; (void)top; (void)height;
''' + actual + "\n}\n"


def vertical_c(text):
    body = method(text, "openPlatter")
    actual = unique(r"^    (NSInteger cutout = \[self cutout\];.*?)^    _dismissView =", body)
    actual = actual.replace("[self cutout]", "Cutout(safeTop)")
    actual = actual.replace("_window.safeAreaInsets.top", "safeTop")
    if "[" in actual or "_window" in actual:
        raise AssertionError("unhandled external vertical-layout dependency")
    return r'''typedef struct { CGFloat top, contentTop, cornerRadius, topInset; } Vertical;
static Vertical VerticalLayout(CGFloat safeTop) {
''' + actual + "\nreturn (Vertical){top,contentTop,cornerRadius,topInset};\n}\n"


class CardGeometryTests(unittest.TestCase):
    def replay(self, functions, main):
        compiler = shutil.which("cc")
        self.assertIsNotNone(compiler, "numeric replay requires the already-installed C compiler")
        # Prefix helpers can be unused in the separate cutout-only executable.
        source = C_PREFIX.replace("static CGRect CGRectMake", "static __attribute__((unused)) CGRect CGRectMake")
        source = source.replace("static CGFloat CGRectGetMidX", "static __attribute__((unused)) CGFloat CGRectGetMidX")
        with tempfile.TemporaryDirectory(prefix="glint-card-", dir=os.environ.get("TMPDIR")) as directory:
            root = Path(directory)
            (root / "probe.c").write_text(source + functions + main)
            command = [compiler, "-std=c11", "-Wall", "-Wextra", "-Werror", str(root / "probe.c"), "-lm", "-o", str(root / "probe")]
            compiled = subprocess.run(command, capture_output=True, text=True, timeout=30)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            return subprocess.run([str(root / "probe")], capture_output=True, text=True, timeout=10)

    def test_cutout_classification_and_integer_contract(self):
        text = CONTROLLER.read_text()
        actual = self.replay(cutout_c(text), r'''
int main(void) {
    const double tops[] = {0,20,43.999,44,47,50.999,51,59};
    const int expected[] = {2,2,2,1,1,1,0,0};
    for (unsigned i=0;i<sizeof(tops)/sizeof(*tops);i++)
        Require(Cutout(tops[i]) == expected[i], "cutout is a 0/1/2 classification");
    puts("GLINT_CARD_CUTOUT_C_PASS"); return 0;
}
''')
        self.assertEqual(actual.returncode, 0, actual.stdout + actual.stderr)
        self.assertIn("- (NSInteger)cutout", method(text, "cutout"))
        self.assertIn("- (NSInteger)cutout;", (SOURCE / "Headers/GLTController.h").read_text())
        self.assertEqual(actual.stdout.strip(), "GLINT_CARD_CUTOUT_C_PASS")
        print(actual.stdout.strip(), flush=True)

    def test_compiled_placement_uses_host_and_original_edge_limits(self):
        text = CONTROLLER.read_text()
        main = r'''
int main(void) {
    const struct { double host,screen,anchorX,anchorW,x,w; } cases[] = {
        {390,390,40,50,6,378}, {320,844,20,40,6,308},
        {430,390,10,30,6,400}, {844,390,790,40,438,400},
        {844,390,400,60,230,400}, {1024,390,480,40,300,400}
    };
    for (unsigned i=0;i<sizeof(cases)/sizeof(*cases);i++) {
        CGRect r=Place(cases[i].host,cases[i].screen,
                       CGRectMake(cases[i].anchorX,10,cases[i].anchorW,20),6,113.25);
        Require(r.origin.x >= 6, "left limit");
        Require(r.origin.x+r.size.width <= cases[i].host-6, "right limit");
        Require(fabs(r.origin.x-cases[i].x)<1e-9, "original x");
        Require(fabs(r.size.width-cases[i].w)<1e-9, "host width and 400pt cap");
        Require(r.origin.y==6 && r.size.height==113.25, "frame carries y and measured height unchanged");
    }
    puts("GLINT_CARD_PLACEMENT_C_PASS"); return 0;
}
'''
        actual = self.replay(placement_c(text), main)
        self.assertEqual(actual.returncode, 0, actual.stdout + actual.stderr)
        self.assertEqual(actual.stdout.strip(), "GLINT_CARD_PLACEMENT_C_PASS")
        body = method(text, "openPlatter")
        for old, new, reason in (
            ("x = MAX(x, 6.0);", "(void)x;", "left limit"),
            ("x = MIN(x, rightLimit);", "(void)rightLimit;", "right limit"),
        ):
            self.assertEqual(body.count(old), 1)
            mutant = text.replace(old, new, 1)
            rejected = self.replay(placement_c(mutant), main)
            self.assertEqual(rejected.returncode, 1, rejected.stdout + rejected.stderr)
            self.assertIn("GLINT_CARD_GEOMETRY_FAIL: " + reason, rejected.stderr)
        print(actual.stdout.strip(), flush=True)

    def test_vertical_insets_and_radii_match_cutout_classes(self):
        text = CONTROLLER.read_text()
        actual = self.replay(cutout_c(text) + vertical_c(text), r'''
int main(void) {
    const struct { double safe,top,row,radius,inset; } cases[] = {
        {0,24,42,22,18}, {20,24,42,22,18}, {43,47,65,22,18},
        {44,6,50,36,44}, {47,6,53,36,47}, {50.999,6,56.999,36,50.999},
        {51,6,62,44,56}, {59,6,62,44,56}
    };
    for (unsigned i=0;i<sizeof(cases)/sizeof(*cases);i++) {
        Vertical v=VerticalLayout(cases[i].safe);
        Require(fabs(v.top-cases[i].top)<1e-9, "shell y");
        Require(fabs(v.contentTop-cases[i].row)<1e-9, "absolute first content row");
        Require(fabs(v.cornerRadius-cases[i].radius)<1e-9, "expanded radius");
        Require(fabs(v.topInset-cases[i].inset)<1e-9, "relative topInset");
    }
    puts("GLINT_CARD_VERTICAL_C_PASS"); return 0;
}
''')
        self.assertEqual(actual.returncode, 0, actual.stdout + actual.stderr)
        self.assertEqual(actual.stdout.strip(), "GLINT_CARD_VERTICAL_C_PASS")
        print(actual.stdout.strip(), flush=True)

    def test_saved_anchor_and_two_stage_expansion_are_wired(self):
        text = CONTROLLER.read_text()
        tap = method(text, "clockTapped")
        self.assertEqual(tap.count("_anchorFrame = [self frameOfClock:clock];"), 1)
        self.assertLess(tap.index("_anchorFrame ="), tap.index("[GLTClock popLabel:clock]"))
        body = method(text, "openPlatter")
        self.assertIn("CGRect anchor = _anchorFrame;", body)
        self.assertIn("initWithFrame:anchor", body)
        self.assertIn("platter.topInset = topInset;", body)
        self.assertIn("platter.layer.cornerRadius = CGRectGetHeight(anchor) * 0.5;", body)
        self.assertIn("platter.frame = openFrame;", body)
        self.assertIn("platter.layer.cornerRadius = cornerRadius;", body)
        self.assertNotIn("UIScreen", body)
        self.assertNotIn("MAX(height, 44)", body)
        self.assertIn("CGAffineTransformScale(", body)
        self.assertIn("CGAffineTransformMakeTranslation(0, -14), 0.94, 0.94)", body)
        self.assertEqual(body.count("[UIView animateWithDuration:"), 2)
        for name, expected in (
            ("kGLTPlatterOpenDuration", 0.6),
            ("kGLTPlatterSpringDamping", 0.72),
        ):
            value = unique(
                r"^static const [^\n]*\b" + name + r"\s*=\s*([^;\n]+);$", text
            )
            self.assertEqual(float(value), expected, name)
        animations = spring_animations(body, text)
        self.assertEqual(len(animations), 2)
        self.assertEqual(
            animations[0],
            (0.6, 0.0, 0.72, 0.4, "UIViewAnimationOptionAllowUserInteraction"),
            "shell animation (duration, delay, damping, velocity, options)",
        )
        self.assertEqual(
            animations[1],
            (0.55, 0.1, 0.8, 0.0, "UIViewAnimationOptionAllowUserInteraction"),
            "content animation (duration, delay, damping, velocity, options)",
        )
        first = body.split("animations:^{", 1)[1].split("} completion:nil]", 1)[0]
        self.assertIn("platter.frame = openFrame;", first)
        self.assertNotIn("content.alpha = 1", first)
        self.assertIn("content.alpha = 1", body.split("animations:^{", 2)[2])

    def test_resize_ignores_unexpanded_shell_and_preserves_frame_snapshot(self):
        text = CONTROLLER.read_text()
        body = method(text, "fitPlatterToContent")
        guard = "if (CGRectGetWidth(platter.frame) < width - 1.0) return;"
        self.assertIn(guard, body)
        self.assertLess(body.index(guard), body.index("heightForWidth:"))
        self.assertIn("CGFloat width = platter.openWidth;", body)
        self.assertNotIn("MAX(", body)
        self.assertEqual(body.count("[UIView animateWithDuration:"), 1)
        self.assertEqual(
            spring_animations(body, text),
            [(0.35, 0.0, 0.85, 0.0,
              "UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState")],
            "resize animation (duration, delay, damping, velocity, options)",
        )
        before_animation = body.split("[UIView animateWithDuration:", 1)[0]
        self.assertIn("CGRect frame = platter.frame;", before_animation)
        self.assertIn("frame.size.height = [platter heightForWidth:width];", before_animation)
        self.assertIn("[platter layoutIfNeeded];", body)

    def test_accepted_hooks_scene_and_unauthorized_preferences_stay_frozen(self):
        text = CONTROLLER.read_text()
        expected = "e3f8b428f71b71e91a99ed9c6ede4ddbf40221b4557fe41e086dd8ecb169e2a0"
        self.assertEqual(protected_controller(text), expected)
        header = (SOURCE / "Headers/GLTController.h").read_bytes()
        old, new = b"- (double)cutout;", b"- (NSInteger)cutout;"
        self.assertEqual(header.count(old) + header.count(new), 1)
        self.assertEqual(hashlib.sha256(header.replace(new, old)).hexdigest(),
                         "736e3d5eb90ba86799b553e3a6031c0455d91c7ac1213c99f27b239f9efa7f0e")
        for path, digest in (
            ("Tweak.xm", "6c2c17de816b55b43b5e7e780ebf5cca54dd5bd97c9d5dece7e777a6df198a33"),
            ("Sources/GLTClock.m", "fe9cbe44f54eadf1baad271f03fbad2d91969bc0ea7c2239b2717b653928c13f"),
        ):
            self.assertEqual(hashlib.sha256((SOURCE / path).read_bytes()).hexdigest(), digest, path)
        prefs = (SOURCE / "Sources/GLTPrefs.m").read_text()
        prefs_digest = "ce59ebf0e579134fa1c2c7cf736cba41405227724b5f0fe23a89e5725198850a"
        self.assertEqual(protected_preferences(prefs), prefs_digest)
        self.assertNotEqual(protected_preferences(prefs.replace('fallback:NO', 'fallback:YES', 1)), prefs_digest)
        for anchor in ("#pragma mark - Pill catalogue\n\n", "// Backed by the __const tables"):
            for replacement in ("", anchor + "\n" + anchor):
                with self.assertRaises(AssertionError):
                    protected_preferences(prefs.replace(anchor, replacement, 1))
        with self.assertRaises(AssertionError):
            protected_controller(text + "\n- (NSInteger)cutout {\n    return 0;\n}\n")
        self.assertNotEqual(protected_controller(text.replace("- (void)layoutTouchView {", "- (void)layoutTouchView {\n    (void)self;", 1)), expected)


if __name__ == "__main__":
    unittest.main()
