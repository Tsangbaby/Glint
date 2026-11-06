"""Narrow beta2 follow-up contracts, not UIKit corner rendering/device proof."""
from pathlib import Path
import hashlib
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from opacity_contract import inverse_opacity

ROOT = Path(os.environ.get("GLINT_SOURCE_ROOT", Path(__file__).resolve().parents[1]))
CONTROLLER = ROOT / "reconstructed/Sources/GLTController.m"
BASELINE = "fadd14c6f9ca27ea4363c323e9dd398a07100fa9"
RADIUS_WRITE = "        platter.layer.cornerRadius = CGRectGetHeight(anchor) * 0.5;\n"


def production_method(source, name):
    matches = re.findall(r"^- \([^\n)]+\)" + re.escape(name)
                         + r"(?=\s|:)[^{;]*\{\n.*?^\}", source, re.M | re.S)
    if len(matches) != 1:
        raise AssertionError("expected one production method: " + name)
    return matches[0]


def closing_animation(source):
    body = production_method(source, "closePlatterAnimated")
    if body.count("animations:^{") != 1 or body.count("} completion:cleanup];") != 1:
        raise AssertionError("expected one closing animation boundary")
    return body.split("animations:^{", 1)[1].split("} completion:cleanup];", 1)[0]


def normalize_platter_refinement(source):
    """Inverse only the confirmed close-radius write; beta2 inverse stays exact."""
    closing = production_method(source, "closePlatterAnimated")
    if closing.count(RADIUS_WRITE) != 1 or RADIUS_WRITE not in closing_animation(source):
        raise AssertionError("closing radius inverse must be unique and in the animation")
    restored = closing.replace(RADIUS_WRITE, "", 1)
    if hashlib.sha256(restored.encode()).hexdigest() != "d4ac9588ac9d694fc6941f0237c113ceb84f95dcbcd5516b21b10781bfcb94cd":
        raise AssertionError("unapproved closing change outside the radius write")
    return source.replace(closing, restored, 1)


def radius_replay(source):
    """Execute only exact production corner assignments with explicit C receivers.

    The predecessor has no corner write and remains compilable: its unchanged
    expanded radius fails the compact-radius assertion, not extraction/compilation.
    This arithmetic seam cannot emulate Core Animation or UIView scheduling.
    """
    animation = closing_animation(source)
    writes = re.findall(r"platter\.layer\.cornerRadius\s*=\s*[^;]+;", animation)
    statements = "\n".join(writes).replace("platter.layer.cornerRadius", "radius")
    statements = statements.replace("CGRectGetHeight(anchor)", "anchorHeight")
    if "[" in statements or "." in statements.replace("0.5", ""):
        raise AssertionError("unhandled production radius dependency")
    return "double CloseRadius(double radius, double anchorHeight) {\n(void)anchorHeight;\n" + statements + "\nreturn radius;\n}\n"


class PlatterRefinementTests(unittest.TestCase):
    def test_closing_radius_reaches_pill_half_height_in_the_shell_transaction(self):
        source = CONTROLLER.read_text()
        animation = closing_animation(source)
        self.assertIn(RADIUS_WRITE.strip(), animation,
                      "the compact shell must not retain the expanded corner radius")
        self.assertLess(animation.index("platter.frame = anchor;"),
                        animation.index(RADIUS_WRITE.strip()))
        self.assertLess(animation.index(RADIUS_WRITE.strip()),
                        animation.index("[platter layoutIfNeeded];"))
        for forbidden in ("CABasicAnimation", "CASpringAnimation", "CADisplayLink", "UIViewPropertyAnimator"):
            self.assertNotIn(forbidden, animation)

    def test_compiled_actual_radius_write_and_executable_predecessor_negative_control(self):
        source = CONTROLLER.read_text()
        baseline = subprocess.check_output(["git", "show", BASELINE + ":reconstructed/Sources/GLTController.m"],
                                           cwd=ROOT, text=True)
        main = r'''
#include <math.h>
#include <stdio.h>
int main(void) {
    const double expanded[] = {22,36,44};
    const double heights[] = {16,22,26,34,38};
    for (unsigned i=0;i<3;i++) for (unsigned j=0;j<5;j++) {
        double radius=CloseRadius(expanded[i],heights[j]);
        if (fabs(radius-heights[j]*0.5)>1e-9) {
            fputs("GLINT_COMPACT_RADIUS_FAIL: expanded radius survives compact endpoint\n",stderr);
            return 1;
        }
    }
    puts("GLINT_COMPACT_RADIUS_C_PASS"); return 0;
}
'''
        compiler = shutil.which("clang") or shutil.which("cc")
        if compiler is None:
            self.fail("C compiler required for the compact-radius replay")
        with tempfile.TemporaryDirectory(prefix="glint-compact-radius-", dir=os.environ.get("TMPDIR")) as directory:
            directory = Path(directory)
            for name, production, expected in (("candidate", source, 0), ("predecessor", baseline, 1)):
                path = directory / (name + ".c")
                binary = directory / name
                path.write_text(radius_replay(production) + main)
                built = subprocess.run([compiler, "-std=c11", "-Wall", "-Wextra", "-Werror", str(path), "-lm", "-o", str(binary)],
                                       capture_output=True, text=True, timeout=30)
                self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
                run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
                self.assertEqual(run.returncode, expected, run.stdout + run.stderr)
                if expected:
                    self.assertIn("GLINT_COMPACT_RADIUS_FAIL: expanded radius survives compact endpoint", run.stderr)
                else:
                    self.assertEqual(run.stdout.strip(), "GLINT_COMPACT_RADIUS_C_PASS")
                    print(run.stdout.strip(), flush=True)

    def test_inverse_preserves_every_other_controller_byte_and_rejects_other_edits(self):
        source = inverse_opacity(CONTROLLER.read_text(), "Sources/GLTController.m")
        baseline = subprocess.check_output(["git", "show", BASELINE + ":reconstructed/Sources/GLTController.m"],
                                           cwd=ROOT, text=True)
        self.assertEqual(normalize_platter_refinement(source), baseline)
        with self.assertRaisesRegex(AssertionError, "unapproved closing change"):
            normalize_platter_refinement(source.replace("usingSpringWithDamping:1.0", "usingSpringWithDamping:0.5", 1))
        with self.assertRaisesRegex(AssertionError, "closing radius inverse"):
            normalize_platter_refinement(source.replace(RADIUS_WRITE, "", 1))
        with self.assertRaisesRegex(AssertionError, "closing radius inverse"):
            normalize_platter_refinement(source.replace(RADIUS_WRITE, RADIUS_WRITE * 2, 1))


if __name__ == "__main__":
    unittest.main()
