"""Replay existing status-bar color/draw hooks; not handset rendering proof."""
from pathlib import Path
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from opacity_contract import inverse_opacity, CLOCK_METHODS

ROOT = Path(__file__).resolve().parents[1]
TWEAK = ROOT / "reconstructed/Tweak.xm"
BASELINE = "fadd14c6f9ca27ea4363c323e9dd398a07100fa9"
OLD_COLOR = """    if ([GLTClock isStyled:self] && ![GLTClock isRendering]) {
        return;
    }
    ((GLTSetObjectIMP)glt_orig_setTextColor)(self, _cmd, color);
"""
NEW_COLOR = """    if ([GLTClock isStyled:self] && ![GLTClock isRendering]) {
        color = [GLTPrefs sharedPrefs].textColor;
    }
    ((GLTSetObjectIMP)glt_orig_setTextColor)(self, _cmd, color);
"""
DRAW_INSERT = """        UIColor *color = [GLTPrefs sharedPrefs].textColor;
        if (![[(UILabel *)self textColor] isEqual:color]) {
            ((GLTSetObjectIMP)glt_orig_setTextColor)(self, @selector(setTextColor:), color);
        }
"""
DRAW_ANCHOR = "static void glt_drawTextInRect(id self, SEL _cmd, CGRect rect) {\n    if ([GLTClock isStyled:self]) {\n"


def hook(text, name):
    matches = re.findall(r"^static void " + re.escape(name) + r"\([^\n]+\) \{\n.*?^\}", text, re.M | re.S)
    if len(matches) != 1:
        raise AssertionError("expected one production hook: " + name)
    return matches[0]


def normalize_statusbar_readability(raw):
    # Preserve original CRLF bytes. Only two exact named hook hunks may differ.
    for after, before in ((NEW_COLOR, OLD_COLOR), (DRAW_ANCHOR + DRAW_INSERT, DRAW_ANCHOR)):
        a, b = after.replace("\n", "\r\n").encode(), before.replace("\n", "\r\n").encode()
        if raw.count(a) != 1:
            raise AssertionError("status-bar readability inverse must be exact and unique")
        raw = raw.replace(a, b, 1)
    if hashlib.sha256(raw).hexdigest() != "6c2c17de816b55b43b5e7e780ebf5cca54dd5bd97c9d5dece7e777a6df198a33":
        raise AssertionError("unapproved status-bar hook change")
    return raw


C_HOST = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef void *id;
typedef int SEL;
typedef int UIColor;
typedef struct { double x,y; } CGPoint;
typedef struct { double width,height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;
typedef struct { double top,left,bottom,right; } UIEdgeInsets;
typedef struct { UIColor *textColor; } UILabel;
typedef struct { UIColor *textColor; } Prefs;
typedef void (*GLTSetObjectIMP)(id,SEL,id);
typedef void (*GLTDrawTextIMP)(id,SEL,CGRect);
static int styled,rendering,writes,draws,reads;
static UIColor black,white,other;
static Prefs prefs;
static CGRect drawn;
static void Require(int ok,const char *reason) {
    if(!ok){fprintf(stderr,"GLINT_STATUSBAR_READABILITY_FAIL: %s\n",reason);exit(1);}
}
static __attribute__((unused)) Prefs ReadPrefs(void){reads++;return prefs;}
static __attribute__((unused)) void RecordSystemColor(id label,UIColor *color){(void)label;(void)color;}
static __attribute__((unused)) int Equal(UIColor *a,UIColor *b){return a==b;}
static UIEdgeInsets Padding(id label){(void)label;return (UIEdgeInsets){1,2,3,4};}
static void SetColor(id self,SEL cmd,id color){Require(cmd==1,"setter selector");writes++;((UILabel *)self)->textColor=color;}
static void Draw(id self,SEL cmd,CGRect rect){Require(cmd==2,"draw selector");(void)self;draws++;drawn=rect;}
static GLTSetObjectIMP glt_orig_setTextColor=SetColor;
static GLTDrawTextIMP glt_orig_drawTextInRect=Draw;
/* HOOKS */
int main(int argc,const char **argv){
    if(argc!=2)return 2;
    UILabel label={&black};CGRect rect={{10,20},{100,40}};
    prefs.textColor=&white;
    if(!strcmp(argv[1],"setter")){
        styled=1;rendering=0;glt_setTextColor(&label,1,&black);
        Require(writes==1 && label.textColor==&white,"styled native setter must forward once with effective foreground");
        rendering=1;glt_setTextColor(&label,1,&other);
        Require(writes==2 && label.textColor==&other,"own render color passes unchanged");
        styled=0;rendering=0;reads=0;glt_setTextColor(&label,1,&black);
        Require(writes==3 && label.textColor==&black && reads==0,"unstyled setter stays native");
    }else if(!strcmp(argv[1],"draw")){
        styled=1;glt_drawTextInRect(&label,2,rect);
        Require(label.textColor==&white && writes==1 && draws==1,"draw must repair foreground drift before original drawing");
        Require(drawn.origin.x==12 && drawn.origin.y==21 && drawn.size.width==94 && drawn.size.height==36,"accepted pill padding");
        glt_drawTextInRect(&label,2,rect);
        Require(writes==1 && draws==2,"matching color avoids repeated setter work");
        prefs.textColor=&black;glt_drawTextInRect(&label,2,rect);
        Require(writes==2 && label.textColor==&black && draws==3,"new effective foreground is not stale");
        styled=0;reads=0;label.textColor=&other;glt_drawTextInRect(&label,2,rect);
        Require(writes==2 && draws==4 && label.textColor==&other && reads==0,"unstyled draw stays native");
        Require(drawn.origin.x==10 && drawn.origin.y==20 && drawn.size.width==100 && drawn.size.height==40,"unstyled rect unchanged");
    }else return 3;
    puts("GLINT_STATUSBAR_READABILITY_C_PASS");return 0;
}
'''


def c_source(source):
    body = hook(source, "glt_setTextColor") + "\n" + hook(source, "glt_drawTextInRect")
    for before, after in (
        ("[GLTClock isStyled:self]", "styled"),
        ("[GLTClock isRendering]", "rendering"),
        ("[GLTPrefs sharedPrefs]", "ReadPrefs()"),
        ("[GLTClock foregroundColorForLabel:self]", "ReadPrefs().textColor"),
        ("[GLTClock setSystemTextColor:color forLabel:self]", "RecordSystemColor(self,color)"),
        ("[GLTClock paddingForLabel:self]", "Padding(self)"),
        ("[[(UILabel *)self textColor] isEqual:color]", "Equal(((UILabel *)self)->textColor,color)"),
        ("@selector(setTextColor:)", "1"),
    ):
        body = body.replace(before, after)
    if "[" in body or "@" in body:
        raise AssertionError("unhandled production hook dependency")
    return C_HOST.replace("/* HOOKS */",body)


NATIVE_HOST = r'''
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define UIColor GLTReadabilityColorFixture
#define UILabel GLTReadabilityLabelFixture
typedef struct { double top,left,bottom,right; } UIEdgeInsets;
@interface UIColor : NSObject @end
@implementation UIColor @end
@interface UILabel : NSObject
@property(nonatomic,strong) UIColor *textColor;
@property(nonatomic,copy) NSAttributedString *attributedText;
@end
@implementation UILabel @end
@interface UILabel (GLTDrawSurface)
- (void)drawTextInRect:(CGRect)rect;
@end
@interface GLTPrefs : NSObject
@property(nonatomic,strong) UIColor *textColor;
@property(nonatomic) double backgroundOpacity;
+(instancetype)sharedPrefs;
@end
static int styled,rendering,writes,draws,reads;
static UIColor *black,*white,*other;
static GLTPrefs *prefs;
static CGRect drawn;
static char kGLTSystemTextColorKey;
static NSString *const NSForegroundColorAttributeName=@"NSColor";
#define _rendering rendering
@implementation GLTPrefs
+(instancetype)sharedPrefs { reads++;return prefs; }
@end
@interface GLTClock : NSObject
+(BOOL)isStyled:(id)label;
+(BOOL)isRendering;
+(UIEdgeInsets)paddingForLabel:(id)label;
+(UIColor *)systemTextColorForLabel:(UILabel *)label;
+(UIColor *)foregroundColorForLabel:(UILabel *)label;
+(void)setSystemTextColor:(UIColor *)color forLabel:(UILabel *)label;
@end
@implementation GLTClock
+(BOOL)isStyled:(id)label { (void)label;return styled; }
+(BOOL)isRendering { return rendering; }
+(UIEdgeInsets)paddingForLabel:(id)label { (void)label;return (UIEdgeInsets){1,2,3,4}; }
/* OPACITY_CLOCK_METHODS */
@end
typedef void (*GLTSetObjectIMP)(id,SEL,id);
typedef void (*GLTDrawTextIMP)(id,SEL,CGRect);
static void Require(int ok,const char *reason) {
    if(!ok){fprintf(stderr,"GLINT_STATUSBAR_READABILITY_FAIL: %s\n",reason);exit(1);}
}
static void SetColor(id self,SEL cmd,id color){
    Require(sel_isEqual(cmd,@selector(setTextColor:)),"setter selector");
    writes++;[(UILabel *)self setTextColor:color];
}
static void Draw(id self,SEL cmd,CGRect rect){
    Require(sel_isEqual(cmd,@selector(drawTextInRect:)),"draw selector");
    (void)self;draws++;drawn=rect;
}
static GLTSetObjectIMP glt_orig_setTextColor=SetColor;
static GLTDrawTextIMP glt_orig_drawTextInRect=Draw;
'''


def native_source(source):
    main = C_HOST.split("int main(",1)[1]
    main = "int main(" + main
    main = main.replace("if(argc!=2)return 2;", "@autoreleasepool {\nblack=[UIColor new];white=[UIColor new];other=[UIColor new];prefs=[GLTPrefs new];\nif(argc!=2)return 2;",1)
    main = main.replace("UILabel label={&black};", "UILabel *label=[UILabel new];label.textColor=black;",1)
    for before,after in (("&black","black"),("&white","white"),("&other","other"),("&label","label"),
                         (",1,",",@selector(setTextColor:),"),(",2,",",@selector(drawTextInRect:),"),
                         ("GLINT_STATUSBAR_READABILITY_C_PASS","GLINT_STATUSBAR_READABILITY_OBJC_PASS")):
        main=main.replace(before,after)
    main=main.rstrip()+"\n}\n"
    main=main.replace('prefs=[GLTPrefs new];','prefs=[GLTPrefs new];prefs.backgroundOpacity=1;',1)
    main=main.replace('if(argc!=2)return 2;','if(argc!=2)return 2;\nif(!strcmp(argv[1],"transparent"))return CheckTransparency();',1)
    actual=(ROOT/'reconstructed/Sources/GLTClock.m').read_text()
    if actual.count(CLOCK_METHODS)!=1:
        raise AssertionError('native color fixture must execute exact current Clock methods')
    prefix=NATIVE_HOST.replace('/* OPACITY_CLOCK_METHODS */',CLOCK_METHODS)
    checks=r'''
static int CheckTransparency(void){
    styled=1;rendering=0;prefs.backgroundOpacity=0;prefs.textColor=white;
    UILabel *label=[UILabel new];label.textColor=white;
    label.attributedText=[[NSAttributedString alloc] initWithString:@"23°C" attributes:@{NSForegroundColorAttributeName:white}];
    glt_setTextColor(label,@selector(setTextColor:),black);
    Require(label.textColor==black && [GLTClock systemTextColorForLabel:label]==black,"transparent foreground uses native black");
    Require([label.attributedText attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL]==black,"transparent attributed run follows native black");
    glt_setTextColor(label,@selector(setTextColor:),white);
    Require(label.textColor==white && [label.attributedText attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL]==white,"native dark-to-light foreground update reaches text");
    Require(rendering==0,"foreground update retires rendering guard");
    prefs.backgroundOpacity=1;
    glt_setTextColor(label,@selector(setTextColor:),black);
    Require(label.textColor==white && [GLTClock systemTextColorForLabel:label]==black,"opaque foreground protected while native color stays fresh");
    prefs.backgroundOpacity=0;
    Require([GLTClock foregroundColorForLabel:label]==black,"return to transparent uses most recent native color");
    puts("GLINT_TRANSPARENT_FOREGROUND_OBJC_PASS");return 0;
}
'''
    return prefix + hook(source,"glt_setTextColor") + "\n" + hook(source,"glt_drawTextInRect") + "\n" + checks + main


class StatusBarReadabilityTests(unittest.TestCase):
    def replay(self, source, mode):
        compiler = shutil.which("clang") or shutil.which("cc")
        if compiler is None:
            raise AssertionError("C compiler required for hook replay")
        with tempfile.TemporaryDirectory(prefix="glint-live-color-",dir=os.environ.get("TMPDIR")) as directory:
            path=Path(directory);(path/"host.c").write_text(c_source(source))
            built=subprocess.run([compiler,"-std=c11","-Wall","-Wextra","-Werror",str(path/"host.c"),"-o",str(path/"host")],text=True,capture_output=True,timeout=30)
            self.assertEqual(built.returncode,0,built.stdout+built.stderr)
            return subprocess.run([str(path/"host"),mode],text=True,capture_output=True,timeout=10)

    def test_existing_setter_forwards_effective_color_without_swallowing_native_update(self):
        result=self.replay(TWEAK.read_text(),"setter")
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_existing_draw_repairs_drift_without_repeated_work_or_unstyled_changes(self):
        result=self.replay(TWEAK.read_text(),"draw")
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_previous_hooks_compile_but_fail_exact_color_ownership_checks(self):
        old=subprocess.check_output(["git","show",BASELINE+":reconstructed/Tweak.xm"],cwd=ROOT,text=True)
        for mode,reason in (("setter","styled native setter must forward once with effective foreground"),
                            ("draw","draw must repair foreground drift before original drawing")):
            result=self.replay(old,mode)
            self.assertEqual(result.returncode,1,result.stdout+result.stderr)
            self.assertIn("GLINT_STATUSBAR_READABILITY_FAIL: "+reason,result.stderr)

    def test_only_exact_setter_and_draw_hunks_change(self):
        raw=inverse_opacity(TWEAK.read_text(),'Tweak.xm').replace('\n','\r\n').encode()
        old=subprocess.check_output(["git","show",BASELINE+":reconstructed/Tweak.xm"],cwd=ROOT)
        self.assertEqual(normalize_statusbar_readability(raw),old)
        for mutant in (raw.replace(b"rect.origin.x    += padding.left;",b"rect.origin.x    -= padding.left;",1),
                       raw.replace(NEW_COLOR.replace("\n","\r\n").encode(),OLD_COLOR.replace("\n","\r\n").encode(),1)):
            with self.assertRaises(AssertionError):
                normalize_statusbar_readability(mutant)

    @unittest.skipUnless(sys.platform=="darwin","requires Apple Foundation; framework doubles are not a handset test")
    def test_unchanged_objective_c_hooks_with_foundation_receivers(self):
        old=subprocess.check_output(["git","show",BASELINE+":reconstructed/Tweak.xm"],cwd=ROOT,text=True)
        with tempfile.TemporaryDirectory(prefix="glint-live-color-objc-",dir=os.environ.get("TMPDIR")) as directory:
            path=Path(directory)
            for name,source,expected in (("candidate",TWEAK.read_text(),0),("previous",old,1)):
                input_path,binary=path/(name+".m"),path/name
                input_path.write_text(native_source(source))
                built=subprocess.run(["xcrun","clang","-fobjc-arc","-fblocks","-Wall","-Wextra","-Werror",
                                      "-framework","Foundation","-framework","CoreGraphics",str(input_path),"-o",str(binary)],
                                     text=True,capture_output=True,timeout=60)
                self.assertEqual(built.returncode,0,built.stdout+built.stderr)
                for mode in (("setter","draw","transparent") if name=="candidate" else ("setter","draw")):
                    run=subprocess.run([str(binary),mode],text=True,capture_output=True,timeout=10)
                    self.assertEqual(run.returncode,expected,run.stdout+run.stderr)
                    marker=("GLINT_TRANSPARENT_FOREGROUND_OBJC_PASS" if mode=="transparent" else "GLINT_STATUSBAR_READABILITY_OBJC_PASS") if not expected else "GLINT_STATUSBAR_READABILITY_FAIL: "
                    self.assertIn(marker,run.stdout+run.stderr)
                    if mode == "transparent":
                        print(marker,flush=True)
        print("GLINT_STATUSBAR_READABILITY_OBJC_PASS: setter + draw + predecessor negatives",flush=True)


if __name__=="__main__":
    unittest.main()
