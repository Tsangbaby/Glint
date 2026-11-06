"""Runtime localization contracts. Darwin additionally executes real Foundation.

Static coverage is not a claim of UIKit rendering or on-device language proof.
"""
from pathlib import Path
import hashlib
import json
import platform
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "reconstructed"
LITERAL = r'@"((?:[^"\\]|\\.)*)"'
LOCALIZED = r'GLTLocalizedString\(\s*(' + LITERAL + r')\s*\)'
INFO_KEYS = {
    "Weather", "Loading the weather…", "Current Location", "Feels like %@ · Rain %ld%%",
    "Sunrise %@ · Sunset %@", "H %@  L %@", "Now", "Weather data by Open-Meteo.com",
    "%@ free of %@", "Storage", "Memory",
}
INTERACTIVE_KEYS = {
    "Not Playing", "Timer", "Timer · Paused", "Today", "Tomorrow", "Alarms", "No alarms are on.",
    "Name or number", "Message", "New Message", "To: ", "Sending…", "Sent",
    "Messaging is disabled in this verification build.",
}
WEATHER_KEYS = {
    "Clear", "Mostly Clear", "Partly Cloudy", "Cloudy", "Fog", "Drizzle", "Freezing Rain",
    "Rain", "Heavy Rain", "Snow", "Showers", "Thunderstorms",
    'Glint can\'t find "%@".',
    "Location is not authorized. Type a city in Glint's settings.",
    "Glint can't find where you are. Type a city in Glint's settings.",
    "The weather isn't available right now.",
}
OPTION_KEYS = {"Time", "Storage & Memory", "Now Playing", "Alarm & Timer", "Weather", "Quick Message", "No alarms", "Off", "Email", "Number", "phone"}


def unquote(value):
    return json.loads('"' + value + '"')


def translations():
    path = SOURCE / "Sources/GLTLocalization.m"
    if not path.is_file():
        raise AssertionError("runtime localization helper is missing (Settings-only localization is insufficient)")
    pairs = re.findall(LITERAL + r'\s*:\s*' + LITERAL, path.read_text())
    result = {}
    for english, chinese in pairs:
        english, chinese = unquote(english), unquote(chinese)
        if english in result:
            raise AssertionError("duplicate runtime translation: " + english)
        result[english] = chinese
    return result


def formats(text):
    # Include escaped percent signs, widths, precision, and length modifiers.
    return re.findall(r'%(?:%|(?:\d+\$)?[-+#0 ]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|ll|[hljztL])?[@diuoxXfFeEgGaAcCsSpn])', text)


class RuntimeLocalizationTests(unittest.TestCase):
    def test_removed_information_cards_are_absent(self):
        info = (SOURCE / "Sources/GLTInfoPlatters.m").read_text()
        for symbol in ("GLTMakeEventsPlatter", "GLTRemindersPlatterView", "GLTMakeRemindersPlatter",
                       "GLTMakeCountdownPlatter", "GLTMakeUnlocksPlatter", "GLTMakeDevicePlatter", "GLTMakeDevicesPlatter",
                       "GLTEvents", "GLTUnlocks", "GLTDevice", "EKEvent", "EKReminder", "GLTInfoStatistic"):
            with self.subTest(symbol=symbol):
                self.assertNotIn(symbol, info)
        for symbol in ("GLTMakeWeatherPlatter", "GLTMakeStoragePlatter", "GLTMakeNotificationPlatter",
                       "GLTInfoCurrentSystemUsage", "weather.sunrises.firstObject", "weather.sunsets.firstObject"):
            self.assertIn(symbol, info)

    def test_runtime_dictionary_covers_fixed_labels_and_formats(self):
        mapping = translations()
        self.assertFalse((INFO_KEYS | INTERACTIVE_KEYS | WEATHER_KEYS | OPTION_KEYS) - mapping.keys())
        for english, chinese in mapping.items():
            with self.subTest(english=english):
                self.assertRegex(chinese, r"[\u3400-\u9fff]")
                self.assertEqual(formats(english), formats(chinese), "printf ABI/percent mismatch")
                self.assertEqual(english.count("·"), chinese.count("·"), "preserve separator glyphs")
        self.assertIn("Open-Meteo.com", mapping["Weather data by Open-Meteo.com"])
        self.assertTrue(mapping["To: "].endswith(" "), "recipient prefix must separate dynamic data")

    def test_shared_helper_covers_every_runtime_callsite(self):
        mapping = translations()
        for path in (SOURCE / "Sources").glob("*.m"):
            keys = {unquote(match[1]) for match in re.findall(LOCALIZED, path.read_text())}
            self.assertFalse(keys - mapping.keys(), f"untranslated runtime keys in {path.name}: {keys - mapping.keys()}")

    def test_recipient_type_fallbacks_are_localized_without_rewriting_contact_data(self):
        source = (SOURCE / "Sources/GLTModels.m").read_text()
        for key in ("Email", "Number", "phone"):
            self.assertIn('GLTLocalizedString(@"' + key + '")', source)
        self.assertIn('recipient.name = name;', source)
        self.assertIn('recipient.address = phone.value.stringValue;', source)
        self.assertIn('recipient.address = email.value;', source)

    def test_retained_cards_bind_only_fixed_ui_strings(self):
        for name, expected in (("GLTInfoPlatters.m", INFO_KEYS), ("GLTInteractivePlatters.m", INTERACTIVE_KEYS)):
            source = (SOURCE / "Sources" / name).read_text()
            bound = {unquote(match[1]) for match in re.findall(LOCALIZED, source)}
            self.assertEqual(bound, expected, name)
            calls = re.findall(r'GLTLocalizedString\(', source)
            self.assertEqual(len(calls), len(re.findall(LOCALIZED, source)), "do not translate notification/song/contact/user data")
            unbound = re.sub(LOCALIZED, "", source)
            for literal in re.findall(LITERAL, unbound):
                self.assertNotIn(unquote(literal), expected, "unlocalized runtime state")

    def test_helper_uses_system_language_and_english_fallback_without_host_bundle_resources(self):
        header = SOURCE / "Headers/GLTLocalization.h"
        self.assertTrue(header.is_file(), "missing shared localization declaration")
        self.assertIn("#import <Foundation/Foundation.h>", header.read_text())
        self.assertIn("NSString *GLTLocalizedString(NSString *english)", header.read_text())
        helper = (SOURCE / "Sources/GLTLocalization.m").read_text()
        self.assertRegex(helper, r'preferredLocalizationsFromArray:\s*@\[@"en", @"zh-Hans"\]\s+forPreferences:\s*\[NSLocale preferredLanguages\]')
        self.assertIn('.firstObject', helper)
        self.assertIn('isEqualToString:@"zh-Hans"', helper)
        self.assertRegex(helper, r'return\s+\w+\[english\]\s*\?:\s*english;')
        self.assertRegex(helper, r'if\s*\(!english\)\s*return\s+@"";')
        self.assertNotRegex(helper, r'mainBundle|bundleForClass|localizedStringForKey|NSUserDefaults|AppleLanguages|setLocale:|/Library/|/var/')

    def test_card_geometry_data_and_lifecycle_are_unchanged_after_unwrapping_text(self):
        expected = {'GLTInfoPlatters.m': '6dac74454d37c238b4921bedbced5d513eb1cd3a79bb2f62fad683b194037c25', 'GLTInteractivePlatters.m': 'fb3e48412d44715eae78aa9d86fe52eb282b6009a78d36dfdd68638defd54fca'}
        for name, digest in expected.items():
            source = (SOURCE / "Sources" / name).read_text()
            english = re.sub(LOCALIZED, lambda m: m.group(1), source)
            self.assertEqual(hashlib.sha256(english.encode()).hexdigest(), digest, name)


    @unittest.skipUnless(platform.system() == "Darwin", "requires real Apple Foundation (no UIKit doubles)")
    def test_apple_foundation_system_language_matching_and_fallback(self):
        # Replace only the read-only NSLocale language getter in this test host.
        # Production helper and Apple's NSBundle language matching run unchanged.
        host = r'''#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "GLTLocalization.h"
#include <stdio.h>
#include <stdlib.h>
static NSArray<NSString *> *preferences;
static NSArray<NSString *> *TestLanguages(id object, SEL selector) { return preferences; }
static void Check(BOOL condition, const char *name) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", name); exit(1); }
}
int main(void) {
    @autoreleasepool {
        Method getter = class_getClassMethod([NSLocale class], @selector(preferredLanguages));
        IMP original = method_setImplementation(getter, (IMP)TestLanguages);
        preferences = @[@"zh-Hans-CN"];
        Check([GLTLocalizedString(@"Storage") isEqualToString:@"存储"], "Simplified Chinese storage");
        Check([GLTLocalizedString(@"Timer · Paused") isEqualToString:@"计时器 · 已暂停"], "paused timer");
        Check([[NSString stringWithFormat:GLTLocalizedString(@"Feels like %@ · Rain %ld%%"), @"20°", (long)75]
               isEqualToString:@"体感 20° · 降雨 75%"], "format ABI and percent");
        Check([[NSString stringWithFormat:GLTLocalizedString(@"%@ free of %@"), @"2 GB", @"8 GB"]
               isEqualToString:@"可用 2 GB，共 8 GB"], "capacity argument order");
        Check([[NSString stringWithFormat:GLTLocalizedString(@"Glint can't find \"%@\"."), @"Paris"]
               isEqualToString:@"Glint 找不到“Paris”。"], "dynamic city unchanged");
        Check([GLTLocalizedString(@"Messaging is disabled in this verification build.")
               isEqualToString:@"此验证版本已禁用信息发送。"], "disabled guard label");
        NSString *unknown = @"Unknown user text";
        Check(GLTLocalizedString(unknown) == unknown, "unknown key English identity fallback");
        Check([GLTLocalizedString(nil) isEqualToString:@""], "nil safety");
        Check([GLTLocalizedString(@"") isEqualToString:@""], "empty safety");
        preferences = @[@"en-GB"];
        Check([GLTLocalizedString(@"Storage") isEqualToString:@"Storage"], "English unchanged after Chinese");
        preferences = @[@"fr-FR", @"en"];
        Check([GLTLocalizedString(@"Weather") isEqualToString:@"Weather"], "unsupported English fallback");
        preferences = @[@"fr-FR", @"zh-Hans"];
        Check([GLTLocalizedString(@"Weather") isEqualToString:@"天气"], "second supported system preference");
        method_setImplementation(getter, original);
        puts("Foundation localization: Chinese, English, unsupported/unknown/nil, formats PASS");
    }
    return 0;
}
'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "host.m").write_text(host)
            build = subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-framework", "Foundation",
                                    "-I", str(SOURCE / "Headers"), str(path / "host.m"),
                                    str(SOURCE / "Sources/GLTLocalization.m"), "-o", str(path / "host")],
                                   capture_output=True, text=True)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            result = subprocess.run([str(path / "host")], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("formats PASS", result.stdout)


if __name__ == "__main__":
    unittest.main()
