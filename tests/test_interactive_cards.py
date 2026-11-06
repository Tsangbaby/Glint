"""Original-backed source contracts; not UIKit execution or device acceptance."""
from pathlib import Path
import ctypes
import hashlib
import os
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "reconstructed/Sources/GLTInteractivePlatters.m"


def english_source():
    # Strip only fixed localization wrappers. Runtime coverage/format tests
    # separately require them; rendering/lifecycle bytes remain protected here.
    return re.sub(r'GLTLocalizedString\((@"(?:\\.|[^"\\])*")\)', r'\1', SOURCE.read_text())


def section(name):
    text = english_source()
    return text.split("@implementation " + name, 1)[1].split("\n@end", 1)[0]


def method(body, signature):
    start = body.index(signature)
    opening = body.index("{", start)
    depth = 1
    for end in range(opening + 1, len(body)):
        if body[end] == "{":
            depth += 1
        elif body[end] == "}":
            depth -= 1
            if not depth:
                return body[opening + 1:end]
    raise AssertionError("unclosed method")


class InteractiveCards(unittest.TestCase):
    def test_media_original_empty_state_and_controls_presentation(self):
        # arm64 a4f0aabf…: 0xe060 tint=.6, 0xe100 16pt semibold,
        # 0xe178 14pt regular; 0xe3a4 11pt monospaced medium;
        # 0xe568 controls spacing=44 + 0xe6bc centerX; 0xecbc hide empty
        # artist, 0xed7c center fallback, 0xeeb0 clamp progress, 0xeee4
        # refresh play image at 30pt with UIImageSymbolWeightSemibold (=6).
        media = section("GLTMediaPlatterView")
        init = method(media, "- (instancetype)initWithFrame:")
        refresh = method(media, "- (void)refresh")
        for fragment in [
            '_titleLabel = GLTMakeLabel(@"Not Playing", 16, UIFontWeightSemibold',
            '_artistLabel = GLTMakeLabel(@"", 14, UIFontWeightRegular',
            '_artworkView.tintColor = [UIColor colorWithWhite:1 alpha:0.6]',
            'monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium',
            'controls.spacing = 44',
            '[controls.centerXAnchor constraintEqualToAnchor:controlsHost.centerXAnchor]',
            '@[header, _track, times, controlsHost]',
            '[body setCustomSpacing:6 afterView:_track]',
        ]:
            self.assertIn(fragment, init)
        self.assertIn('_artistLabel.hidden = _artistLabel.text.length == 0', refresh)
        self.assertIn('MAX(0.0, MIN(1.0, elapsed / duration))', refresh)
        self.assertNotIn('return;', refresh)  # Empty and populated states share reset path.
        self.assertIn('configurationWithPointSize:30', refresh)
        self.assertIn('weight:UIImageSymbolWeightSemibold', refresh)
        control = method(media, '- (UIButton *)controlWithSymbol:')
        self.assertIn('weight:UIImageSymbolWeightSemibold', control)
        self.assertIn('GLTMediaTimeString(elapsed)', refresh)
        self.assertIn('GLTMediaTimeString(duration - elapsed)', refresh)
        helper = SOURCE.read_text().split('static NSString *GLTMediaTimeString', 1)[1].split('\n}', 1)[0]
        self.assertIn('llround(MAX(0, interval))', helper)
        self.assertNotIn('hours', helper)  # Original media remains minutes:seconds above one hour.

    def test_clock_paused_timer_and_alarm_day_details(self):
        # 0x11b50..0x11ba4 accepts fireDate OR pausedTimerRemaining>0;
        # UTF16 CFString 0x2d630 = Timer · Paused; 0x11bf8 size=40,
        # 0x11c3c monospaced light; 0x11da8 18pt after timer track.
        # 0x11e48 no date + short time, 0x120ac Today / 0x120f0 Tomorrow
        # else EEEE; 0x12198 day · title; 0x1220c horizontal row spacing10.
        clock = section('GLTClockPlatterView')
        init = method(clock, '- (instancetype)initWithFrame:')
        rebuild = method(clock, '- (void)rebuild')
        tick = method(clock, '- (void)tick')
        self.assertIn('_stack.spacing = 12', init)
        for fragment in [
            '_countdown = nil', '_track = nil', '_fill = nil',
            'items.timerFireDate || items.pausedTimerRemaining > 0',
            'items.timerFireDate ? @"Timer" : @"Timer · Paused"',
            'monospacedDigitSystemFontOfSize:40 weight:UIFontWeightLight',
            '[_stack setCustomSpacing:18 afterView:_track]',
            'formatter.dateStyle = NSDateFormatterNoStyle',
            'formatter.timeStyle = NSDateFormatterShortStyle',
            'dateFormatFromTemplate:@"EEEE"', 'isDateInToday:alarm.fireDate',
            'isDateInTomorrow:alarm.fireDate', '@"Today"', '@"Tomorrow"',
            '@"%@ · %@", day, alarm.title',
            'GLTMakeLabel([formatter stringFromDate:alarm.fireDate], 22',
            'column.axis = UILayoutConstraintAxisHorizontal',
            'column.spacing = 10', 'column.alignment = UIStackViewAlignmentFirstBaseline',
            'MIN((NSUInteger)4, alarms.count)', '@"No alarms are on."',
        ]:
            self.assertIn(fragment, rebuild)
        self.assertIn('items.timerFireDate ? [items.timerFireDate timeIntervalSinceNow]', tick)
        self.assertIn(': items.pausedTimerRemaining', tick)
        self.assertIn('items.timerDuration > 0 ? 1.0 - remaining / items.timerDuration : 0', tick)
        self.assertIn('MAX(0.0, MIN(1.0, fraction))', tick)
        helper = SOURCE.read_text().split('static NSString *GLTClockString', 1)[1].split('\n}', 1)[0]
        self.assertIn('(long long)ceil(MAX(0, interval))', helper)
        self.assertIn('if (hours > 0)', helper)

    def test_compose_header_recipient_clear_and_three_suggestion_limit(self):
        # 0x136a4..0x136b0 clearRecipient target, 0x138f4 New Message,
        # 0x1394c stack10; helper 0x13a00: font16, placeholder .4,
        # background .1, radius18, padding14, height36, dark keyboard.
        # 0x13ef0 limit3, 0x140cc detail != name; 0x144a8 uses address
        # (not detail) in chip, 0x146ac excludes _sending from readiness.
        compose = section('GLTComposePlatterView')
        init = method(compose, '- (instancetype)initWithFrame:')
        suggestions = method(compose, '- (void)showSuggestions:')
        choose = method(compose, '- (void)chooseRecipient:')
        for fragment in [
            '_toField = GLTComposeField(@"Name or number")',
            '_messageField = GLTComposeField(@"Message")',
            '[_recipientChip addTarget:self action:@selector(clearRecipient)',
            'GLTMakeLabel(@"New Message", 13, UIFontWeightSemibold',
            '@[heading, _toField, _recipientChip, _suggestions, input, _statusLabel]',
            'body.spacing = 10', '_statusLabel.hidden = YES',
            '_recipientChip.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold]',
        ]:
            self.assertIn(fragment, init)
        self.assertIn('MIN((NSUInteger)3, recipients.count)', suggestions)
        self.assertIn('recipient.detail.length && ![recipient.detail isEqualToString:recipient.name]', suggestions)
        self.assertIn('systemFontOfSize:15 weight:UIFontWeightSemibold', suggestions)
        self.assertIn('systemFontOfSize:13]', suggestions)
        self.assertIn('[NSString stringWithFormat:@"%@  ·  %@", recipient.name, recipient.address]', choose)
        self.assertNotIn('recipient.detail', choose)
        self.assertIn('&& !_sending', method(compose, '- (void)updateSendButton'))
        helper = SOURCE.read_text().split('static UITextField *GLTComposeField', 1)[1].split('\n}', 1)[0]
        for fragment in [
            'systemFontOfSize:16', 'colorWithWhite:1 alpha:0.4',
            'colorWithWhite:1 alpha:0.1', 'cornerRadius = 18',
            'CGRectMake(0, 0, 14, 0)', 'leftViewMode = UITextFieldViewModeAlways',
            'keyboardAppearance = UIKeyboardAppearanceDark', 'constraintEqualToConstant:36',
        ]:
            self.assertIn(fragment, helper)

    def test_extracted_numeric_statements_on_host(self):
        # Only C arithmetic is executed: no Objective-C/Foundation/UIKit shim.
        # Keep exact production statements, substituting named provider values.
        text = SOURCE.read_text()
        functions = []
        for label, helper in [('media', 'GLTMediaTimeString'), ('clock', 'GLTClockString')]:
            body = text.split('static NSString *' + helper, 1)[1].split('\n}', 1)[0]
            statements = re.findall(r'long long total = [^;]+;', body)
            self.assertEqual(len(statements), 1)
            functions.append('long long ' + label + '(double interval) {' + statements[0] + 'return total;}')
        media_refresh = method(section('GLTMediaPlatterView'), '- (void)refresh')
        fraction = re.findall(r'_fraction = ([^;]+);', media_refresh)
        self.assertEqual(len(fraction), 1)
        functions.append('double mediaFraction(double elapsed, double duration) {return ' + fraction[0] + ';}')
        clock_tick = method(section('GLTClockPlatterView'), '- (void)tick')
        statements = re.findall(r'(?:double )?fraction = [^;]+;', clock_tick)
        self.assertEqual(len(statements), 2)
        functions.append('double timerFraction(double remaining, double duration) {' +
                         ''.join(statements).replace('items.timerDuration', 'duration') + 'return fraction;}')
        code = '#include <math.h>\n#define MAX(a,b) ((a)>(b)?(a):(b))\n#define MIN(a,b) ((a)<(b)?(a):(b))\n' + '\n'.join(functions)
        scratch = os.environ.get('TMPDIR', str(Path.home() / '.hermes/cache/scratch'))
        with tempfile.TemporaryDirectory(prefix='glint-interactive-', dir=scratch) as directory:
            cfile = Path(directory) / 'numeric.c'
            library = Path(directory) / 'numeric.so'
            cfile.write_text(code)
            subprocess.run(['cc', '-shared', '-fPIC', str(cfile), '-lm', '-o', str(library)],
                           capture_output=True, text=True, check=True)
            lib = ctypes.CDLL(str(library))
            for label in ['media', 'clock']:
                function = getattr(lib, label)
                function.argtypes = [ctypes.c_double]
                function.restype = ctypes.c_longlong
            for interval, media, clock in [(-1, 0, 0), (0, 0, 0), (0.1, 0, 1),
                                           (0.5, 1, 1), (59.1, 59, 60),
                                           (59.9, 60, 60), (3600.1, 3600, 3601)]:
                self.assertEqual(lib.media(interval), media)
                self.assertEqual(lib.clock(interval), clock)
            for label in ['mediaFraction', 'timerFraction']:
                function = getattr(lib, label)
                function.argtypes = [ctypes.c_double, ctypes.c_double]
                function.restype = ctypes.c_double
            for elapsed, duration, expected in [(-1, 60, 0), (15, 60, .25), (90, 60, 1), (10, 0, 0)]:
                self.assertEqual(lib.mediaFraction(elapsed, duration), expected)
            for remaining, duration, expected in [(90, 60, 0), (45, 60, .25), (0, 60, 1), (10, 0, 0)]:
                self.assertEqual(lib.timerFraction(remaining, duration), expected)

    def test_submission_and_lifecycle_bytes_remain_baseline(self):
        text = english_source()
        self.assertEqual(hashlib.sha256(text.split('#pragma mark - Sending', 1)[1].encode()).hexdigest(),
                         '00022a489020421f4372dd96bed6cf0b7332015093689e727a0b0e7f9bcbd957')
        expected = {
            'GLTMediaPlatterView': '39e52356f5dc77bddf8fa8c5cf403afc1366f754537410234fdebc23d5557af1',
            'GLTClockPlatterView': '1679dcd6b4c609c142d3dde4d51f3f9520a581da81a16fcfcb2d7d9f51f7d006',
            'GLTComposePlatterView': '2bf5296aba16f096e0edc4eceb06086c79d27bed13f2449ae632d73052070523',
        }
        for name, digest in expected.items():
            lifecycle = method(section(name), '- (void)didMoveToWindow')
            self.assertEqual(hashlib.sha256(lifecycle.encode()).hexdigest(), digest)
        raw = SOURCE.read_bytes()
        self.assertEqual(raw.count(b'\n'), raw.count(b'\r\n'))


if __name__ == "__main__":
    unittest.main()
