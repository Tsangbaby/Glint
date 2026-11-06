"""Compile exact production C helpers; UIKit integration is source-contract only."""
import ctypes
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
PREFS = ROOT / "reconstructed/Sources/GLTPrefs.m"
EVIDENCE = Path(os.environ.get("GLT_CONTRAST_EVIDENCE", str(Path(os.environ.get("TMPDIR", Path.home() / ".cache")) / "glint-contrast")))


def production_function(source, name):
    matches = list(re.finditer(r"^static (?:double|int|BOOL|UIColor \*)\s*" + re.escape(name) + r"\([^;]*?\)\s*\{", source, re.M))
    if len(matches) != 1:
        raise AssertionError(f"Expected one production helper {name}; found {len(matches)}")
    start = matches[0].start()
    depth = 1
    end = matches[0].end()
    while depth and end < len(source):
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    if depth:
        raise AssertionError(f"Unclosed production helper {name}")
    return source[start:end]


def compiled_helpers(source=None):
    if source is None:
        source = PREFS.read_text()
    helpers = "\n\n".join(production_function(source, name) for name in (
        "GLTLinearizedSRGB", "GLTRelativeLuminance", "GLTReadableForeground"))
    host = "#include <math.h>\n" + helpers + """
double test_luminance(double r, double g, double b) {
    return GLTRelativeLuminance(r, g, b);
}
int test_choice(double br, double bg, double bb, double pr, double pg, double pb) {
    return GLTReadableForeground(GLTRelativeLuminance(br, bg, bb),
                                 GLTRelativeLuminance(pr, pg, pb));
}
int test_luminance_choice(double background, double preferred) {
    return GLTReadableForeground(background, preferred);
}
"""
    digest = hashlib.sha256(host.encode()).hexdigest()
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    c_path = EVIDENCE / f"contrast-{digest}.c"
    library_path = EVIDENCE / f"contrast-{digest}.so"
    c_path.write_text(host)
    compiler = shutil.which("clang") or shutil.which("cc")
    if not compiler:
        raise AssertionError("A C compiler is required; numeric coverage cannot be skipped")
    result = subprocess.run([compiler, "-std=c99", "-shared", "-fPIC", "-Wall", "-Wextra", "-Werror", "-O2", str(c_path), "-lm", "-o", str(library_path)], capture_output=True, text=True)
    if result.returncode:
        raise AssertionError(f"Production helper compilation failed: {result.stdout}{result.stderr}")
    library = ctypes.CDLL(str(library_path))
    library.test_luminance.argtypes = [ctypes.c_double] * 3
    library.test_luminance.restype = ctypes.c_double
    library.test_choice.argtypes = [ctypes.c_double] * 6
    library.test_choice.restype = ctypes.c_int
    library.test_luminance_choice.argtypes = [ctypes.c_double] * 2
    library.test_luminance_choice.restype = ctypes.c_int
    return library


def rgb(hex_color):
    return tuple(int(hex_color[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


class PillContrastTests(unittest.TestCase):
    def test_unreadable_colors_choose_maximum_wcag_contrast(self):
        library = compiled_helpers()
        # Same foreground/background is unreadable. -1 means black, +1 white.
        cases = [
            ("000000", 0.0, 1), ("FFFFFF", 1.0, -1),
            ("333333", 0.033104766570885055, 1),
            ("0A0A0A", 0.003035269835488375, 1),
            ("0B0B0B", 0.0033465357638991604, 1),
            ("666666", 0.13286832155381798, 1),
            ("FFFF00", 0.9278, -1), ("FF0000", 0.2126, -1),
            ("00FF00", 0.7152, -1), ("0000FF", 0.0722, 1),
            ("FF00FF", 0.2848, -1), ("00FFFF", 0.7874, -1),
        ]
        for color, luminance, choice in cases:
            with self.subTest(color=color):
                channels = rgb(color)
                self.assertAlmostEqual(library.test_luminance(*channels), luminance, places=12)
                self.assertEqual(library.test_choice(*channels, *channels), choice)
                contrast = (luminance + 0.05) / 0.05 if choice == -1 else 1.05 / (luminance + 0.05)
                self.assertGreaterEqual(contrast, 4.5)

    def test_readable_preferred_colors_are_preserved_at_threshold(self):
        library = compiled_helpers()
        # The preferred color is retained, not merely replaced with the same pole.
        for background, preferred in [("000000", "FFFF00"), ("FFFFFF", "0000FF"),
                                      ("000000", "FF0000"), ("000000", "757575"),
                                      ("FFFFFF", "767676")]:
            with self.subTest(background=background, preferred=preferred):
                self.assertEqual(library.test_choice(*rgb(background), *rgb(preferred)), 0)
        # Adjacent 8-bit grays straddle 4.5:1 in opposite directions.
        self.assertEqual(library.test_choice(*rgb("000000"), *rgb("747474")), 1)
        self.assertEqual(library.test_choice(*rgb("FFFFFF"), *rgb("777777")), -1)
        # Adjacent saturated reds cross the threshold against black as well.
        self.assertEqual(library.test_choice(*rgb("000000"), *rgb("EA0000")), 1)
        self.assertEqual(library.test_choice(*rgb("000000"), *rgb("EB0000")), 0)
        self.assertEqual(library.test_luminance_choice(0.05, 0.4), 0)
        self.assertEqual(library.test_luminance_choice(0.05, 0.4 - 1e-9), 1)
        self.assertEqual(library.test_luminance_choice(0.05, 0.4 + 1e-9), 0)

    def test_reload_adapts_only_effective_color_and_preserves_raw_preferences(self):
        source = PREFS.read_text()
        effective_line = '    _textColor = GLTEffectiveTextColor(GLTColorFromString([self objectForKey:@"textColor"]) ?: [UIColor whiteColor], _backgroundColor);'
        self.assertIn(effective_line, source)
        adapter = production_function(source, "GLTEffectiveTextColor")
        self.assertIn("if (!background) return preferred;", adapter)
        self.assertIn("!GLTGetOpaqueLuminance(background, &backgroundLuminance)", adapter)
        self.assertIn("!GLTGetOpaqueLuminance(preferred, &preferredLuminance)", adapter)
        self.assertIn("return preferred;", adapter)
        self.assertIn("GLTReadableForeground(backgroundLuminance, preferredLuminance)", adapter)
        self.assertIn("if (foreground == 0) return preferred;", adapter)
        self.assertIn("foreground < 0 ? [UIColor blackColor] : [UIColor whiteColor]", adapter)
        decoder = production_function(source, "GLTGetOpaqueLuminance")
        self.assertIn("getRed:&red green:&green blue:&blue alpha:&alpha", decoder)
        self.assertIn("getWhite:&white alpha:&alpha", decoder)
        self.assertIn("red = green = blue = white;", decoder)
        self.assertIn("alpha != 1.0", decoder)
        for channel in ("red", "green", "blue"):
            self.assertIn(f"{channel} >= 0.0 && {channel} <= 1.0", decoder)
        self.assertIn("return NO;", decoder)
        self.assertIn("*luminance = GLTRelativeLuminance(red, green, blue);", decoder)
        # Freeze all unrelated bytes, including parser, raw readers, keys and writes.
        baseline = subprocess.check_output(["git", "show", "2fad941aa78c15b306a8cf8f3494d13a5ee137ac:reconstructed/Sources/GLTPrefs.m"], cwd=ROOT).decode()
        original_line = '    _textColor = GLTColorFromString([self objectForKey:@"textColor"]) ?: [UIColor whiteColor];'
        inverse = re.sub(r"#pragma mark - Effective text contrast\n.*?(?=#pragma mark - Reload)", "", source, count=1, flags=re.S)
        self.assertEqual(inverse.replace(effective_line, original_line), baseline)

    def test_source_extraction_rejects_missing_or_duplicate_helpers(self):
        source = PREFS.read_text()
        helper = production_function(source, "GLTReadableForeground")
        with self.assertRaisesRegex(AssertionError, "found 0"):
            production_function(source.replace(helper, ""), "GLTReadableForeground")
        with self.assertRaisesRegex(AssertionError, "found 2"):
            production_function(source + "\n" + helper, "GLTReadableForeground")

    def test_compiled_mutations_reach_numeric_regression_assertions(self):
        source = PREFS.read_text()
        no_preservation = source.replace(">= 4.5) return 0;", ">= 22.0) return 0;", 1)
        self.assertNotEqual(no_preservation, source)
        broken = compiled_helpers(no_preservation)
        with self.assertRaisesRegex(AssertionError, "1 != 0"):
            self.assertEqual(broken.test_choice(*rgb("000000"), *rgb("FFFF00")), 0)
        linearizer = production_function(source, "GLTLinearizedSRGB")
        no_gamma = source.replace(linearizer, "static double GLTLinearizedSRGB(double component) { return component; }", 1)
        broken = compiled_helpers(no_gamma)
        with self.assertRaises(AssertionError):
            self.assertAlmostEqual(broken.test_luminance(*rgb("333333")), 0.033104766570885055, places=12)

    def test_existing_live_preview_and_progress_consumers_share_effective_color(self):
        controller = (ROOT / "reconstructed/Sources/GLTController.m").read_text()
        clock = (ROOT / "reconstructed/Sources/GLTClock.m").read_text()
        content = (ROOT / "reconstructed/Sources/GLTPillContent.m").read_text()
        self.assertIn("textColor:prefs.textColor", controller)
        self.assertGreaterEqual(controller.count("color:prefs.textColor"), 2)
        self.assertIn("[content attributedStringWithFont:label.font color:textColor]", clock)
        self.assertIn("label.textColor = textColor;", clock)
        self.assertIn("NSForegroundColorAttributeName: color", content)
        self.assertIn("GLTProgressAttachment(_progress, font, color)", content)
        self.assertIn("imageWithTintColor:_imageTint", content)


if __name__ == "__main__":
    unittest.main()
