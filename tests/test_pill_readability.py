"""Execute the custom-color adapter with explicit C color transports.

Selectors are mechanically translated, not reimplemented. This checks adapter
control flow, not UIKit conversion, status-bar overrides or device rendering.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

from test_pill_contrast import production_function

PREFS = Path(__file__).resolve().parents[1] / "reconstructed/Sources/GLTPrefs.m"

C_TRANSPORT = r'''
#include <math.h>
#include <stdio.h>
#include <string.h>
typedef int BOOL;
typedef double CGFloat;
#define YES 1
#define NO 0
typedef struct { double r, g, b, a; int rgb, gray; } Color;
static Color kBlack = {0,0,0,1,1,1}, kWhite = {1,1,1,1,1,1};
static BOOL ReadRGB(Color *c, double *r, double *g, double *b, double *a) {
    if (!c || !c->rgb) return NO;
    *r=c->r; *g=c->g; *b=c->b; *a=c->a; return YES;
}
static BOOL ReadWhite(Color *c, double *w, double *a) {
    if (!c || !c->gray) return NO;
    *w=c->r; *a=c->a; return YES;
}
'''


def production_adapter(source):
    names = ("GLTLinearizedSRGB", "GLTRelativeLuminance", "GLTReadableForeground",
             "GLTGetOpaqueLuminance", "GLTEffectiveTextColor")
    body = "\n\n".join(production_function(source, name) for name in names)
    for before, after in (
        ("UIColor *", "Color *"),
        ("[color getRed:&red green:&green blue:&blue alpha:&alpha]",
         "ReadRGB(color, &red, &green, &blue, &alpha)"),
        ("[color getWhite:&white alpha:&alpha]", "ReadWhite(color, &white, &alpha)"),
        ("[UIColor blackColor]", "&kBlack"),
        ("[UIColor whiteColor]", "&kWhite"),
    ):
        body = body.replace(before, after)
    if "[" in body or "UIColor" in body:
        raise AssertionError("unhandled production Objective-C dependency")
    return body


MAIN = r'''
static int Require(int ok, const char *reason) {
    if (!ok) fprintf(stderr,"GLINT_READABILITY_FAIL: %s\n",reason);
    return ok;
}
int main(int argc, const char **argv) {
    if (argc != 2) return 2;
    Color dark={16.0/255,0,0,1,1,0}, yellow={1,1,0,1,1,0};
    Color greyBlack={0,0,0,1,0,1}, unknown={0,0,0,1,0,0};
    Color translucent={0,0,0,0.5,1,0}, invalid={-0.1,0,0,1,1,0};
    if (!strcmp(argv[1],"custom")) {
        if (!Require(GLTEffectiveTextColor(&dark,&kBlack)==&kWhite,
                     "custom black background must resolve dark preferred text to white")) return 1;
        if (!Require(GLTEffectiveTextColor(&kBlack,&greyBlack)==&kWhite,
                     "grayscale extraction must reach readable white")) return 1;
        if (!Require(GLTEffectiveTextColor(&kWhite,&kWhite)==&kBlack,
                     "white-on-white must resolve to black")) return 1;
        if (!Require(GLTEffectiveTextColor(&yellow,&kBlack)==&yellow,
                     "readable saved color must remain unchanged")) return 1;
    } else if (!strcmp(argv[1],"transport-rejection")) {
        if (!Require(GLTEffectiveTextColor(&dark,&unknown)==&dark,
                     "unknown color extraction preserves preference")) return 1;
        if (!Require(GLTEffectiveTextColor(&dark,&translucent)==&dark,
                     "alpha rejection preserves preference")) return 1;
        if (!Require(GLTEffectiveTextColor(&dark,&invalid)==&dark,
                     "range rejection preserves preference")) return 1;
        if (!Require(GLTEffectiveTextColor(&unknown,&kBlack)==&unknown,
                     "unknown preferred extraction preserves preference")) return 1;
    } else if (!strcmp(argv[1],"default-control")) {
        if (!Require(GLTEffectiveTextColor(&dark,NULL)==&dark,
                     "default style stays outside this custom-style repair")) return 1;
    } else return 7;
    puts("GLINT_READABILITY_ADAPTER_PASS"); return 0;
}
'''


class PillReadabilityTests(unittest.TestCase):
    def replay(self, source, mode):
        compiler = shutil.which("clang") or shutil.which("cc")
        if compiler is None:
            raise AssertionError("C compiler required for actual adapter replay")
        with tempfile.TemporaryDirectory(prefix="glint-readability-", dir=os.environ.get("TMPDIR")) as work:
            root = Path(work)
            path, binary = root / "adapter.c", root / "adapter"
            path.write_text(C_TRANSPORT + production_adapter(source) + MAIN)
            built = subprocess.run([compiler,"-std=c11","-Wall","-Wextra","-Werror",str(path),"-lm","-o",str(binary)],
                                   text=True,capture_output=True,timeout=30)
            self.assertEqual(built.returncode,0,built.stdout+built.stderr)
            return subprocess.run([str(binary),mode],text=True,capture_output=True,timeout=10)

    def test_actual_custom_adapter_and_preservation_branches(self):
        for mode in ("custom","transport-rejection","default-control"):
            result = self.replay(PREFS.read_text(),mode)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertEqual(result.stdout.strip(),"GLINT_READABILITY_ADAPTER_PASS")

    def test_disabled_decoder_or_adapter_reaches_custom_readability_failure(self):
        source = PREFS.read_text()
        for anchor, early_return in (
            ("static BOOL GLTGetOpaqueLuminance(UIColor *color, double *luminance) {", "return NO;"),
            ("static UIColor *GLTEffectiveTextColor(UIColor *preferred, UIColor *background) {", "return preferred;"),
        ):
            self.assertEqual(source.count(anchor),1)
            broken = source.replace(anchor,anchor+"\n    "+early_return,1)
            result = self.replay(broken,"custom")
            self.assertEqual(result.returncode,1,result.stdout+result.stderr)
            self.assertIn("GLINT_READABILITY_FAIL: custom black background must resolve dark preferred text to white",result.stderr)


if __name__ == "__main__":
    unittest.main()
