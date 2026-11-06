"""Settings resource/source contracts; not an Apple Preferences/UI execution.

XML property lists are a supported .strings representation, parsed here without
installing an OpenStep parser. Runtime/device language switching remains an
Apple-host verification step.
"""
from pathlib import Path
import plistlib
import re
import unittest
from opacity_contract import with_opacity_row

ROOT = Path(__file__).resolve().parents[1]
PREFS = ROOT / "reconstructed/prefs"
RESOURCES = PREFS / "Resources"


def strings(locale, table):
    path = RESOURCES / (locale + ".lproj") / (table + ".strings")
    if not path.is_file():
        raise AssertionError("missing Settings localization table: " + str(path))
    result = plistlib.loads(path.read_bytes())
    if not isinstance(result, dict) or not all(
        isinstance(k, str) and isinstance(v, str) and v for k, v in result.items()
    ):
        raise AssertionError(".strings must contain nonempty string translations")
    return result


def root_texts():
    result = set()
    document = plistlib.loads((RESOURCES / "Root.plist").read_bytes())
    for item in document["items"]:
        for field in ("label", "footerText", "placeholder"):
            if item.get(field):
                result.add(item[field])
        result.update(item.get("validTitles", []))
    return result


def custom_texts():
    document = plistlib.loads((RESOURCES / "Root.plist").read_bytes())
    return {item["format"] for item in document["items"] if "format" in item} | {"Version %@"}


class LocalizationTests(unittest.TestCase):
    def test_every_settings_text_has_preserved_english_and_simplified_chinese(self):
        for table, expected in (("Root", root_texts()), ("Localizable", custom_texts())):
            english = strings("en", table)
            chinese = strings("zh-Hans", table)
            self.assertEqual(set(english), expected, table)
            self.assertEqual(set(chinese), expected, table)
            for key in expected:
                with self.subTest(table=table, key=key):
                    self.assertEqual(english[key], key, "English wording must be preserved")
                    if key == "%.0f%%":
                        self.assertEqual(chinese[key], key)
                    else:
                        self.assertRegex(chinese[key], r"[\u3400-\u9fff]", "missing Chinese text")
                    self.assertEqual(re.findall(r"%(?:\d+\$)?[.\d]*[@dfiu]", english[key]),
                                     re.findall(r"%(?:\d+\$)?[.\d]*[@dfiu]", chinese[key]),
                                     "printf arguments must retain type/order/precision")


    def test_root_schema_only_changes_the_authorized_feature_selection_and_groups(self):
        from test_beta1_settings import expected_root
        self.assertEqual(plistlib.loads((RESOURCES / "Root.plist").read_bytes()), with_opacity_row(expected_root()))

    def test_bundle_declares_system_languages_and_english_fallback(self):
        info = plistlib.loads((RESOURCES / "Info.plist").read_bytes())
        self.assertEqual(info["CFBundleDevelopmentRegion"], "en")
        self.assertEqual(info.get("CFBundleLocalizations"), ["en", "zh-Hans"])
        source = (PREFS / "GLTRootListController.m").read_text()
        self.assertIn("localizedStringForKey:english value:english table:table", source)
        self.assertNotIn("mainBundle", source)
        self.assertNotRegex(source, r"NSUserDefaults|AppleLanguages|setLocale:|/Library/")
        for table, expected in (("Root", root_texts()), ("Localizable", custom_texts())):
            self.assertEqual(strings(info["CFBundleDevelopmentRegion"], table),
                             {key: key for key in expected})

    def test_loader_and_native_title_dictionaries_use_the_prefs_bundle(self):
        source = (PREFS / "GLTRootListController.m").read_text()
        self.assertIn("bundleForClass:[GLTRootListController class]", source)
        self.assertIn('loadSpecifiersFromPlistName:@"Root" target:self bundle:bundle', source)
        # Preferences consumes native value->title dictionaries, not a late
        # mutation of the raw validTitles array. Preserve the original keys.
        self.assertIn("specifier.titleDictionary = GLTLocalizedTitles(bundle, specifier.titleDictionary)", source)
        self.assertIn("specifier.shortTitleDictionary = GLTLocalizedTitles(bundle, specifier.shortTitleDictionary)", source)
        self.assertIn("for (id value in titles)", source)
        self.assertIn('localized[value] = GLTLocalizedSetting(bundle, titles[value], @"Root")', source)
        self.assertNotRegex(source, r'setProperty:.*forKey:@"(?:values|validValues|default|defaults|key)"')

    def test_all_loaded_display_fields_are_localized(self):
        source = (PREFS / "GLTRootListController.m").read_text()
        self.assertIn('specifier.name = GLTLocalizedSetting(bundle, specifier.name, @"Root")', source)
        self.assertIn('@[@"footerText", @"placeholder"]', source)
        self.assertIn('[specifier propertyForKey:key]', source)
        self.assertIn('[specifier setProperty:GLTLocalizedSetting(bundle, english, @"Root") forKey:key]', source)
        self.assertIn('GLTLocalizedSetting([NSBundle bundleForClass:[GLTRootListController class]],', source)
        self.assertIn('@"Version %@", @"Localizable")', source)

    def test_custom_units_use_localizable_and_system_pickers_keep_their_locale(self):
        source = (PREFS / "GLTCells.m").read_text()
        self.assertIn('[NSBundle bundleForClass:cellClass]', source)
        self.assertIn('localizedStringForKey:english value:english table:@"Localizable"', source)
        self.assertIn('_format = GLTLocalizedCellString([GLTSliderCell class], properties[@"format"] ?: @"%.1f")', source)
        self.assertNotIn('mainBundle', source)
        self.assertNotRegex(source, r'AppleLanguages|NSUserDefaults|setLocale:|\.locale\s*=')
        self.assertNotIn('UIDatePicker', source)
        self.assertNotIn('GLTDateCell', source)
        self.assertIn('_colorWell.supportsAlpha = NO;', source)

    def test_custom_cell_persistence_and_controls_remain_byte_bound(self):
        import hashlib
        source = (PREFS / "GLTCells.m").read_text()
        source = re.sub(r"^#pragma mark - Settings localization\n.*?(?=^#pragma mark - Shared persistence)",
                        "", source, flags=re.M | re.S)
        source = source.replace(
            '_format = GLTLocalizedCellString([GLTSliderCell class], properties[@"format"] ?: @"%.1f");',
            '_format = properties[@"format"] ?: @"%.1f";')
        # The removed countdown-only date cell is not a retained control.
        import subprocess
        baseline = subprocess.check_output([
            'git', 'show', 'c4c7817f66a13b8e76677d2e000112cd8bbe7ae5:reconstructed/prefs/GLTCells.m'
        ], cwd=ROOT).decode().split('#pragma mark - Date', 1)[0]
        baseline = re.sub(r"^#pragma mark - Settings localization\n.*?(?=^#pragma mark - Shared persistence)",
                          "", baseline, flags=re.M | re.S).replace(
            '_format = GLTLocalizedCellString([GLTSliderCell class], properties[@"format"] ?: @"%.1f");',
            '_format = properties[@"format"] ?: @"%.1f";')
        self.assertEqual(source.split('#import <Preferences/PSTableCell.h>', 1)[1].rstrip(),
                         baseline.split('#import <Preferences/PSTableCell.h>', 1)[1].rstrip())


if __name__ == "__main__":
    unittest.main()
