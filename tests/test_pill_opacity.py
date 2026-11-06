"""Transparency configuration/production replay; not UIKit appearance proof."""
from pathlib import Path
import os
import re
import plistlib
import subprocess
import tempfile
import unittest
from opacity_contract import ROW, EDITS, HELPER, inverse_opacity, with_opacity_row

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'reconstructed'
BASELINE='fadd14c6f9ca27ea4363c323e9dd398a07100fa9'

class PillOpacityTests(unittest.TestCase):
    def test_settings_add_only_one_default_preserving_background_slider(self):
        current=plistlib.loads((SOURCE/'prefs/Resources/Root.plist').read_bytes())
        old=plistlib.loads(subprocess.check_output(['git','show',BASELINE+':reconstructed/prefs/Resources/Root.plist'],cwd=ROOT))
        self.assertEqual(current,with_opacity_row(old))

    def test_actual_percentage_helper_preserves_default_and_clamps_nonfinite_values(self):
        text=(SOURCE/'Sources/GLTPrefs.m').read_text()
        self.assertIn(HELPER,text,'missing production transparency conversion')
        main=r'''
#include <stdio.h>
int main(void){
 const double inputs[]={0,25,50,75,100,-10,150,NAN,INFINITY,-INFINITY};
 const double expected[]={1,.75,.5,.25,0,1,0,1,1,1};
 for(unsigned i=0;i<sizeof(inputs)/sizeof(*inputs);i++)
  if(fabs(GLTBackgroundOpacity(inputs[i])-expected[i])>1e-12){fputs("GLINT_OPACITY_FAIL\n",stderr);return 1;}
 puts("GLINT_OPACITY_C_PASS");return 0;
}
'''
        with tempfile.TemporaryDirectory(prefix='glint-opacity-',dir=os.environ.get('TMPDIR')) as work:
            p=Path(work);(p/'a.c').write_text('#include <math.h>\n'+HELPER+main)
            c=subprocess.run(['clang','-std=c11','-Wall','-Wextra','-Werror',str(p/'a.c'),'-lm','-o',str(p/'a')],capture_output=True,text=True)
            self.assertEqual(c.returncode,0,c.stdout+c.stderr)
            r=subprocess.run([str(p/'a')],capture_output=True,text=True)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            print(r.stdout.strip(),flush=True)

    def test_opacity_does_not_fade_foreground_or_change_other_source_bytes(self):
        from test_platter_refinement import normalize_platter_refinement
        from test_statusbar_readability import normalize_statusbar_readability
        for path in EDITS:
            raw=(SOURCE/path).read_bytes();text=raw.decode().replace('\r\n','\n')
            inverse=inverse_opacity(text,path)
            if path=='Sources/GLTController.m':inverse=normalize_platter_refinement(inverse)
            if path=='Tweak.xm':inverse=normalize_statusbar_readability(inverse.replace('\n','\r\n').encode()).decode().replace('\r\n','\n')
            old=subprocess.check_output(['git','show',BASELINE+':reconstructed/'+path],cwd=ROOT).decode().replace('\r\n','\n')
            self.assertEqual(inverse,old,path)
        controller=(SOURCE/'Sources/GLTController.m').read_text()
        self.assertNotIn('label.alpha = prefs.backgroundOpacity',controller)
        self.assertNotIn('preview.alpha = prefs.backgroundOpacity',controller)
        clock=(SOURCE/'Sources/GLTClock.m').read_text()
        self.assertIn('if (prefs.backgroundOpacity == 0.0)',clock)
        self.assertIn('return [self systemTextColorForLabel:label] ?: label.textColor ?: prefs.textColor;',clock)
        self.assertIn('value:color range:NSMakeRange(0, string.length)',clock)

if __name__=='__main__':unittest.main()
