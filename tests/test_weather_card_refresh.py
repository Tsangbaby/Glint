"""Weather notification/card ownership regression; not UIKit/device execution.

Linux checks production wiring. Darwin replays the exact callback with recording
Foundation boundary doubles; it does not simulate rendering, Scene or animations.
"""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'reconstructed/Sources/GLTController.m'
HEADER = ROOT / 'reconstructed/Headers/GLTController.h'


def callback():
    text = SOURCE.read_text()
    match = re.search(r'^- \(void\)sourcesChanged:\(NSNotification \*\)note \{\n(.*?)^\}', text, re.M | re.S)
    if match is None:
        raise AssertionError('missing production notification-aware weather callback')
    return match[1]


class WeatherCardOwnership(unittest.TestCase):
    def test_weather_completion_refreshes_only_owned_content_in_existing_shell(self):
        body = callback()
        self.assertIn('[note.object isKindOfClass:[GLTWeather class]]', body)
        self.assertIn('_weatherPlatterContent && _platterView.content == _weatherPlatterContent', body)
        self.assertIn('GLTMakeWeatherPlatter()', body)
        self.assertIn('content.closeHandler = previous.closeHandler', body)
        self.assertIn('content.resizeHandler = previous.resizeHandler', body)
        self.assertIn('_platterView.content = content', body)
        self.assertIn('[self fitPlatterToContent]', body)
        self.assertIn('[self update]', body)
        for forbidden in ('openPlatter:', 'closePlatter', 'currentPill', 'wantsWeather', 'GLTMakeComposePlatter',
                          'GLTMakeMediaPlatter', 'CGRect', 'makeKeyWindow', 'becomeKeyWindow'):
            self.assertNotIn(forbidden, body)
        self.assertIn('__weak GLTPlatterContent *', HEADER.read_text())
        source = SOURCE.read_text()
        self.assertEqual(source.count('selector:@selector(sourcesChanged:)'), 2)
        self.assertNotIn('selector:@selector(sourcesChanged)', source)
        route = source.split('- (GLTPlatterContent *)platterContent {', 1)[1].split('- (void)openPlatter:', 1)[0]
        self.assertIn('_weatherPlatterContent = content', route)

    @unittest.skipUnless(sys.platform == 'darwin', 'requires actual Apple Foundation runtime')
    def test_exact_callback_preserves_shell_and_handlers_without_overwriting_other_cards(self):
        body = callback()
        program = r'''#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
@interface GLTWeather : NSObject @end
@implementation GLTWeather @end
@interface GLTPlatterContent : NSObject
@property(nonatomic, copy) void (^closeHandler)(void);
@property(nonatomic, copy) void (^resizeHandler)(void);
@end
@implementation GLTPlatterContent @end
@interface GLTPlatterView : NSObject
@property(nonatomic, strong) GLTPlatterContent *content;
@end
@implementation GLTPlatterView @end
static NSInteger factories, closes, resizes;
static GLTPlatterContent *GLTMakeWeatherPlatter(void) { factories++; return [GLTPlatterContent new]; }
@interface GLTController : NSObject {
    GLTPlatterView *_platterView;
    __weak GLTPlatterContent *_weatherPlatterContent;
}
@property(nonatomic) NSInteger fits;
@property(nonatomic) NSInteger updates;
- (void)sourcesChanged:(NSNotification *)note;
- (void)attach:(GLTPlatterView *)shell weather:(GLTPlatterContent *)weather;
@end
@implementation GLTController
- (void)attach:(GLTPlatterView *)shell weather:(GLTPlatterContent *)weather {
    _platterView = shell; _weatherPlatterContent = weather;
}
- (void)fitPlatterToContent { self.fits++; }
- (void)update { self.updates++; }
- (void)sourcesChanged:(NSNotification *)note {
''' + body + r'''}
@end
static void check(BOOL value, const char *name) { if (!value) { fprintf(stderr,"FAIL %s\n",name); exit(1); } }
int main(void) { @autoreleasepool {
    GLTController *controller = [GLTController new];
    GLTWeather *weather = [GLTWeather new];
    NSNotification *completion = [NSNotification notificationWithName:@"sources" object:weather];
    GLTPlatterView *shell = [GLTPlatterView new];
    GLTPlatterContent *loading = [GLTPlatterContent new];
    loading.closeHandler = ^{ closes++; };
    loading.resizeHandler = ^{ resizes++; };
    shell.content = loading;
    [controller attach:shell weather:loading];
    [controller sourcesChanged:completion];
    GLTPlatterContent *loaded = shell.content;
    check(loaded != loading && factories == 1 && controller.fits == 1, "replace loading inside same shell");
    loaded.closeHandler(); loaded.resizeHandler();
    check(closes == 1 && resizes == 1, "preserve existing owner callbacks");
    [controller sourcesChanged:completion];
    check(shell.content != loaded && factories == 2 && controller.fits == 2, "next success/failure updates owned weather");
    GLTPlatterContent *unchanged = shell.content;
    [controller sourcesChanged:[NSNotification notificationWithName:@"sources" object:nil]];
    check(shell.content == unchanged && factories == 2, "media and lock events do not rebuild weather");
    GLTPlatterContent *compose = [GLTPlatterContent new];
    shell.content = compose;
    [controller sourcesChanged:completion];
    check(shell.content == compose && factories == 2, "never overwrite compose/media/notification");
    [controller attach:nil weather:unchanged];
    [controller sourcesChanged:completion];
    check(factories == 2, "closed shell stays closed");
    [controller attach:shell weather:nil];
    [controller sourcesChanged:completion];
    check(factories == 2 && controller.updates == 6, "non-weather owned content stays intact; pill still updates");
    puts("GLINT_WEATHER_CARD_OWNER_HOST_PASS");
} return 0; }
'''
        scratch = os.environ.get('TMPDIR', str(Path.home() / '.hermes/cache/scratch'))
        with tempfile.TemporaryDirectory(prefix='glint-weather-owner-', dir=scratch) as directory:
            path = Path(directory)
            (path / 'host.m').write_text(program)
            compiled = subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fblocks', '-framework', 'Foundation',
                                       str(path / 'host.m'), '-o', str(path / 'host')], capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            actual = subprocess.run([str(path / 'host')], capture_output=True, text=True, timeout=15)
            self.assertEqual(actual.returncode, 0, actual.stdout + actual.stderr)
            self.assertIn('GLINT_WEATHER_CARD_OWNER_HOST_PASS', actual.stdout)


if __name__ == '__main__':
    unittest.main()
