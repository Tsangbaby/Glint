"""Original-backed source contracts, NOT UIKit execution or device acceptance.

Glint 1.6.3 arm64 SHA-256:
a4f0aabf448ebc50ddfaf8a2e08dcd2262ae494e01ff0756e9ab64bfa0ddc3bb.
Catalogue: +pillOrder 0x1b81c -> NSConstantArray 0x2f1d8,
15 boxed integer objects at 0x2f028; integer payload is object + 16.
Preview methods: contentForPill 0x7638, weather 0x7cbc, storage 0x8740,
sun 0x89c8, countContent 0x8cb8. Constants are decoded with CFString
encoding flags (including UTF-16), not C-string truncation or screenshot data.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def source(filename):
    text = (ROOT / "reconstructed/Sources" / filename).read_text()
    return re.sub(r"//[^\n]*|/\*.*?\*/", "", text, flags=re.S)


def method(filename, name):
    text = source(filename)
    matches = list(re.finditer(r"^[+-] \([^\n]+\)" + re.escape(name), text, re.M))
    if len(matches) != 1:
        raise AssertionError(f"Expected one production method {name}, got {len(matches)}")
    start = text.index("{", matches[0].end())
    depth, pos = 1, start + 1
    while depth and pos < len(text):
        depth += (text[pos] == "{") - (text[pos] == "}")
        pos += 1
    if depth:
        raise AssertionError(f"Unclosed production method {name}")
    return text[start + 1:pos - 1]


class PillPreviewContracts(unittest.TestCase):
    def test_catalogue_original_order_without_renumbering(self):
        text = method("GLTPrefs.m", "pillOrder")
        self.assertEqual(re.findall(r"@\((GLTPill\w+)\)", text), [
            "GLTPillTime", "GLTPillDate", "GLTPillBattery", "GLTPillNetwork",
            "GLTPillStorage", "GLTPillNowPlaying", "GLTPillNextEvent",
            "GLTPillCalendar", "GLTPillReminders", "GLTPillAlarm",
            "GLTPillCountdown", "GLTPillWeather", "GLTPillSun",
            "GLTPillUnlocks", "GLTPillQuickMessage",
        ])
        names = method("GLTPrefs.m", "nameForPill:")
        self.assertEqual(re.findall(r'@"([^"]*)"', names), [
            "Time", "Date", "Battery", "Network Speed", "Now Playing",
            "Calendar", "Reminders", "Weather", "Alarm & Timer", "Next Event",
            "Sunrise & Sunset", "Storage & Memory", "Countdown", "Unlocks",
            "Quick Message",
        ])

    def test_weather_missing_data_uses_original_utf16_placeholder(self):
        text = method("GLTController.m", "weatherContent")
        self.assertIn('contentWithSymbol:@"cloud.sun" text:@"--°"', text)
        self.assertIn('if (!weather.hasData)', text)
        self.assertIn('[GLTWeather temperatureString:weather.temperature]', text)
        self.assertIn('symbolForCode:weather.code isDay:weather.isDay', text)

    def test_storage_preview_formats_only_free_bytes_with_original_rounding(self):
        text = method("GLTController.m", "storageContent")
        for token in ('attributesOfFileSystemForPath:@"/private/var"',
                      'NSFileSystemFreeSize', 'longLongValue',
                      'free > 10000000000LL',
                      '(double)(unsigned long long)free / 1000000000.0',
                      '__builtin_llround(', '* 1000000000LL',
                      'stringFromByteCount:free', 'NSByteCountFormatterCountStyleFile',
                      'contentWithSymbol:@"internaldrive" text:text'):
            self.assertIn(token, text)
        for token in ('GLTStorageSummary()', 'NSFileSystemSize', 'free of', '@"38 GB"'):
            self.assertNotIn(token, text)

    def test_positive_counts_use_badge_plus_noun_not_repeated_count_or_icon(self):
        text = method("GLTController.m", "countContent:")
        self.assertIn('contentWithSymbol:nil', text)
        self.assertIn('text:(count == 1 ? singular : plural)', text)
        self.assertIn('if (count <= 0)', text)
        self.assertIn('contentWithSymbol:symbol text:none', text)
        self.assertIn('content.badge = count', text)
        self.assertNotIn('stringWithFormat:', text)

    def test_sun_reuses_original_formatter_with_current_provider_flag_contract(self):
        text = method("GLTController.m", "sunContent")
        self.assertIn('[_timeFormatter stringFromDate:date]', text)
        # Original 0x8a30/0x8a40 uses a sunrise flag. This reconstructed
        # provider explicitly returns isSunset; do NOT invert its consumer.
        self.assertIn('sunset ? @"sunset.fill" : @"sunrise.fill"', text)
        self.assertIn('nextSunEvent:&sunset', text)
        provider = method("GLTWeather.m", "nextSunEvent:")
        self.assertIn('if (isSunset) *isSunset = bestIsSunset', provider)
        self.assertIn('bestIsSunset = YES', provider)
        self.assertIn('contentWithSymbol:@"sunrise" text:@"--:--"', text)
        self.assertIn('content.imageTint = [UIColor systemOrangeColor]', text)
        self.assertNotIn('NSDateFormatter new', text)

    def test_preserves_live_date_calendar_icon_and_empty_counts(self):
        text = method("GLTController.m", "contentForPill:")
        date = text.split('case GLTPillDate:', 1)[1].split('case GLTPillBattery:', 1)[0]
        self.assertIn('[_dateFormatter stringFromDate:[NSDate date]]', date)
        self.assertIn('contentWithSymbol:@"calendar" text:text', date)
        for token in ('[self eventsLeftToday]', 'none:@"No events"',
                      '[GLTEvents sharedEvents].reminders.count', 'none:@"All done"'):
            self.assertIn(token, text)
        for screenshot_value in ('@"21:40"', '@"117 unlocks"', '@"70%"'):
            self.assertNotIn(screenshot_value, text)


if __name__ == "__main__":
    unittest.main()
