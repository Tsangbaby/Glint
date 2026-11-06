"""Production-bound shell contracts and optional native lifecycle recording.

Source contracts are not UIKit rendering/scheduling or handset/FPS proof.
The macOS recording seam compiles extracted production methods unchanged
against explicit Foundation/CoreGraphics-backed UIKit receiver doubles.
"""
from pathlib import Path
import hashlib
import os
import re
import platform
import subprocess
import tempfile
import unittest

ROOT = Path(os.environ.get("GLINT_SOURCE_ROOT", Path(__file__).resolve().parents[1]))
CONTROLLER = ROOT / "reconstructed/Sources/GLTController.m"
BASELINE = "2fad941aa78c15b306a8cf8f3494d13a5ee137ac"
HOST = Path(__file__).with_name("platter_motion_host.m")


def method(source, name):
    matches = re.findall(
        r"^- \([^\n)]+\)" + re.escape(name) + r"(?=\s|:)[^{;]*\{\n.*?^\}",
        source, re.M | re.S,
    )
    if len(matches) != 1:
        raise AssertionError("expected one production method: " + name)
    return matches[0]


def normalize_beta2_controller(source):
    """Restore only frozen, explicitly authorized beta2 methods for old byte guards.

    This is never used by behavioral replay. Any additional edit inside these
    methods rejects the inverse; every byte outside them remains visible.
    """
    baseline = subprocess.check_output(
        ["git", "show", BASELINE + ":reconstructed/Sources/GLTController.m"],
        cwd=ROOT, text=True,
    )
    approved = {
        "openPlatter": "b54c81710245cae23d96593ce3d98877d43c099d1976e4e5f35d3f8ed9a208bf",
        "closePlatterAnimated": "d4ac9588ac9d694fc6941f0237c113ceb84f95dcbcd5516b21b10781bfcb94cd",
    }
    for name, digest in approved.items():
        current = method(source, name)
        if hashlib.sha256(current.encode()).hexdigest() != digest:
            raise AssertionError("beta2 changed surface mismatch: " + name)
        source = source.replace(current, method(baseline, name), 1)
    current = "static const CGFloat kGLTPlatterCloseDuration = 0.6;"
    if source.count(current) != 1:
        raise AssertionError("beta2 closing duration inverse is not unique")
    return source.replace(current, "static const CGFloat kGLTPlatterCloseDuration = 0.24;", 1)


def host_source(source):
    """No body rewriting: only exact methods, constants and Weather assignments."""
    shell = (ROOT / "reconstructed/Sources/GLTPlatterView.m").read_text()
    constants = []
    for name, owner in (("kGLTPlatterSpringDamping", source),
                        ("kGLTPlatterOpenDuration", source),
                        ("kGLTPlatterCloseDuration", source),
                        ("kGLTPlatterPadding", shell)):
        values = re.findall(r"^static const [^\n]*\b" + name + r" = [^;]+;$", owner, re.M)
        if len(values) != 1:
            raise AssertionError("expected one production constant: " + name)
        constants.append(values[0])
    weather = method(source, "sourcesChanged")
    copies = []
    for name in ("close", "resize"):
        values = re.findall(r"^        content\." + name + r"Handler = previous\." + name + r"Handler;$", weather, re.M)
        if len(values) != 1:
            raise AssertionError("expected one Weather handler transfer: " + name)
        copies.append(values[0])
    # The host deliberately uses the production receiver identifier, too.
    template = HOST.read_text()
    replacements = {
        "// GLINT_PRODUCTION_CONSTANTS": "\n".join(constants),
        "// GLINT_PRODUCTION_LAYOUT": method(shell, "layoutSubviews"),
        "// GLINT_PRODUCTION_METHODS": "\n\n".join(method(source, name) for name in (
            "cutout", "openPlatter", "closePlatter", "closePlatterAnimated", "fitPlatterToContent")),
        "// GLINT_PRODUCTION_WEATHER_COPY": "\n".join(copies),
    }
    for marker, actual in replacements.items():
        if template.count(marker) != 1:
            raise AssertionError("missing/duplicate host boundary: " + marker)
        template = template.replace(marker, actual)
    return template


class PlatterMotionTests(unittest.TestCase):
    def test_exact_beta2_inverse_preserves_all_other_controller_bytes(self):
        source = CONTROLLER.read_text()
        baseline = subprocess.check_output(
            ["git", "show", BASELINE + ":reconstructed/Sources/GLTController.m"],
            cwd=ROOT, text=True,
        )
        self.assertEqual(normalize_beta2_controller(source), baseline)
        with self.assertRaisesRegex(AssertionError, "beta2 changed surface mismatch: openPlatter"):
            normalize_beta2_controller(source.replace("x = MAX(x, 6.0);", "x = MAX(x, 7.0);", 1))
        mutant = source.replace("- (void)layoutTouchView {", "- (void)layoutTouchView {\n    (void)self;", 1)
        self.assertNotEqual(normalize_beta2_controller(mutant), baseline)

    def test_shell_rounding_and_blur_layout_share_existing_open_spring(self):
        source = CONTROLLER.read_text()
        body = method(source, "openPlatter")
        before, shell, content = body.split("[UIView animateWithDuration:")
        self.assertNotIn("platter.layer.cornerRadius", shell,
                         "radius must not animate independently of the rounded shell bounds")
        self.assertIn("platter.layer.cornerRadius = cornerRadius;", before)
        self.assertLess(before.index("platter.layer.cornerRadius = cornerRadius;"),
                        before.index("[host addSubview:platter];"))
        self.assertIn("[platter layoutIfNeeded];", before)
        self.assertLess(before.index("[platter layoutIfNeeded];"),
                        before.index("[host addSubview:platter];"))
        self.assertIn("platter.frame = openFrame;\n        [platter layoutIfNeeded];", shell)
        self.assertIn("usingSpringWithDamping:kGLTPlatterSpringDamping", shell)
        self.assertIn("initialSpringVelocity:0.4", shell)
        self.assertIn("animateWithDuration:kGLTPlatterOpenDuration", body)
        self.assertIn("animateWithDuration:0.55", body)
        self.assertIn("delay:0.1", content)
        self.assertIn("usingSpringWithDamping:0.8", content)
        self.assertIn("CGAffineTransformMakeTranslation(0, -14), 0.94, 0.94)", before)
        for animation in (shell, content):
            self.assertIn("UIViewAnimationOptionBeginFromCurrentState", animation)
        self.assertRegex(source, r"kGLTPlatterOpenDuration = 0\.6;")
        self.assertRegex(source, r"kGLTPlatterSpringDamping = 0\.72;")

    def test_close_retracts_whole_shell_in_nonovershooting_interruptible_spring(self):
        source = CONTROLLER.read_text()
        body = method(source, "closePlatterAnimated")
        self.assertIn("platter.frame = anchor;", body,
                      "closing must retract the material shell, not only fade its content")
        self.assertIn("CGRect anchor = _anchorFrame;", body)
        self.assertLess(body.index("CGRect anchor = _anchorFrame;"),
                        body.index("_platterView = nil;"))
        self.assertIn("platter.frame = anchor;\n        [platter layoutIfNeeded];", body)
        self.assertIn("usingSpringWithDamping:1.0", body)
        self.assertIn("initialSpringVelocity:0", body)
        self.assertIn("delay:0", body)
        self.assertIn("UIViewAnimationOptionBeginFromCurrentState", body)
        self.assertIn("CGAffineTransformMakeTranslation(0, -14), 0.94, 0.94)", body)
        self.assertNotIn("CGAffineTransformConcat", body)
        self.assertRegex(source, r"kGLTPlatterCloseDuration = 0\.6;")
        self.assertEqual(body.count("[UIView animateWithDuration:"), 1)
        self.assertIn("if (!animated) {\n        cleanup(YES);\n        return;", body)
        for forbidden in ("platter.alpha", ".effect =", "CABasicAnimation", "UIViewPropertyAnimator",
                          "CADisplayLink", "snapshot", "shouldRasterize"):
            self.assertNotIn(forbidden, body)

    def test_retiring_shell_callbacks_cannot_close_or_resize_replacement(self):
        source = CONTROLLER.read_text()
        opening = method(source, "openPlatter")
        closing = method(source, "closePlatterAnimated")
        self.assertIn("__weak GLTPlatterView *weakPlatter = platter;", opening,
                      "Weather copies handlers: callbacks must belong to a shell, not just a controller")
        for name, action in (("close", "closePlatter"), ("resize", "fitPlatterToContent")):
            block = re.search(r"content\." + name + r"Handler = \^\{(.*?)\n    \};", opening, re.S)
            assert block is not None
            body = block[1]
            self.assertIn("GLTController *strongSelf = weakSelf;", body)
            self.assertIn("GLTPlatterView *currentPlatter = weakPlatter;", body)
            self.assertIn("if (!strongSelf || !currentPlatter || strongSelf->_platterView != currentPlatter) return;", body)
            self.assertIn("[strongSelf " + action + "];", body)
        for statement in ("platter.userInteractionEnabled = NO;",
                          "platter.content.closeHandler = nil;",
                          "platter.content.resizeHandler = nil;"):
            self.assertIn(statement, closing)
            self.assertLess(closing.index("_platterView = nil;"), closing.index(statement))
            self.assertLess(closing.index(statement), closing.index("[_window endEditing:YES];"))
        cleanup = closing.split("void (^cleanup)(BOOL) =", 1)[1].split("};", 1)[0]
        self.assertIn("[platter removeFromSuperview];", cleanup)
        self.assertNotIn("_platterView =", cleanup)

    def test_host_extracts_exact_production_bodies_with_fail_closed_boundaries(self):
        source = CONTROLLER.read_text()
        actual = host_source(source)
        for name in ("openPlatter", "closePlatterAnimated", "fitPlatterToContent"):
            self.assertIn(method(source, name), actual)
        baseline = subprocess.check_output(
            ["git", "show", BASELINE + ":reconstructed/Sources/GLTController.m"], cwd=ROOT,
            text=True,
        )
        self.assertIn(method(baseline, "closePlatterAnimated"), host_source(baseline))
        with self.assertRaisesRegex(AssertionError, "expected one production method"):
            host_source(source + "\n" + method(source, "openPlatter"))
        with self.assertRaisesRegex(AssertionError, "expected one production constant"):
            host_source(source.replace("kGLTPlatterCloseDuration =", "otherDuration =", 1))
        with self.assertRaisesRegex(AssertionError, "expected one Weather handler transfer"):
            host_source(source.replace("content.closeHandler = previous.closeHandler;", "", 1))

    @unittest.skipUnless(platform.system() == "Darwin", "requires native macOS Foundation/CoreGraphics; not UIKit/device proof")
    def test_native_production_extracted_lifecycle_with_negative_controls(self):
        source = CONTROLLER.read_text()
        baseline = subprocess.check_output(
            ["git", "show", BASELINE + ":reconstructed/Sources/GLTController.m"], cwd=ROOT, text=True,
        )
        with tempfile.TemporaryDirectory(prefix="glint-motion-", dir=os.environ.get("TMPDIR")) as directory:
            directory = Path(directory)

            def build(label, production):
                path = directory / (label + ".m")
                path.write_text(host_source(production))
                binary = directory / label
                result = subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra",
                                         "-Wno-unused-parameter", "-framework", "Foundation", "-framework", "CoreGraphics",
                                         str(path), "-o", str(binary)], capture_output=True, text=True, timeout=60)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                return binary

            candidate = build("candidate", source)
            rejected = build("accepted-predecessor", baseline)
            for mode, failure in (("rounding", "rounded shell initialized before mount"),
                                  ("close", "whole shell retracts to captured pill"),
                                  ("lifecycle", "retiring shell deauthorized synchronously")):
                good = subprocess.run([str(candidate), mode], capture_output=True, text=True, timeout=10)
                self.assertEqual(good.returncode, 0, good.stdout + good.stderr)
                self.assertIn("GLINT_MOTION_HOST_PASS", good.stdout)
                bad = subprocess.run([str(rejected), mode], capture_output=True, text=True, timeout=10)
                self.assertEqual(bad.returncode, 1, bad.stdout + bad.stderr)
                self.assertIn("GLINT_MOTION_HOST_FAIL: " + failure, bad.stderr)
                print("GLINT_MOTION_NATIVE_PASS: " + mode + " + executable predecessor negative control", flush=True)
            guard = "if (!strongSelf || !currentPlatter || strongSelf->_platterView != currentPlatter) return;"
            self.assertEqual(source.count(guard), 2)
            mutant = build("missing-identity-guard", source.replace(guard, ""))
            bad = subprocess.run([str(mutant), "lifecycle"], capture_output=True, text=True, timeout=10)
            self.assertEqual(bad.returncode, 1, bad.stdout + bad.stderr)
            self.assertIn("GLINT_MOTION_HOST_FAIL: retained old callbacks cannot mutate replacement shell", bad.stderr)


if __name__ == "__main__":
    unittest.main()
