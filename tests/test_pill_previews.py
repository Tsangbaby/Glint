"""Retained preview contracts and beta1 absence checks; not device execution.

Original Glint 1.6.3 arm64 SHA256:
a4f0aabf448ebc50ddfaf8a2e08dcd2262ae494e01ff0756e9ab64bfa0ddc3bb.
Original +pillOrder 0x1b81c -> 0x2f1d8; content 0x7638, weather 0x7cbc,
storage 0x8740. The retained order is the original list with the requested nine
entries removed; persisted integer identities are not renumbered.
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
    def test_catalogue_retains_original_relative_order_and_only_kept_names(self):
        self.assertEqual(re.findall(r"@\((GLTPill\w+)\)", method("GLTPrefs.m", "pillOrder")), [
            "GLTPillTime", "GLTPillStorage", "GLTPillNowPlaying", "GLTPillAlarm",
            "GLTPillWeather", "GLTPillQuickMessage",
        ])
        names = method("GLTPrefs.m", "nameForPill:")
        self.assertCountEqual(re.findall(r'GLTLocalizedString\(@"([^"]*)"\)', names), [
            "Time", "Now Playing", "Weather", "Alarm & Timer", "Storage & Memory", "Quick Message",
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

    def test_removed_preview_methods_and_provider_lookups_are_absent(self):
        controller = source("GLTController.m")
        weather = source("GLTWeather.m")
        for token in ("countContent:", "sunContent", "networkContent", "nextEventContent", "eventsLeftToday",
                      "_dateFormatter", "GLTPillDate", "GLTPillBattery", "GLTPillNetwork", "GLTPillNextEvent",
                      "GLTPillCalendar", "GLTPillReminders", "GLTPillCountdown", "GLTPillSun", "GLTPillUnlocks",
                      "GLTEvents", "GLTUnlocks", "GLTConnectedDevices"):
            self.assertNotIn(token, controller)
        self.assertNotIn("nextSunEvent:", weather)
        # Native time/date-view replacement ownership is not the deleted Date pill.
        self.assertIn("_dateViews", controller)
        self.assertIn("_timeFormatter", controller)

    def test_remaining_previews_use_live_sources_not_old_screenshot_values(self):
        text = method("GLTController.m", "contentForPill:")
        for token in ("GLTPillTime", "GLTPillNowPlaying", "GLTPillAlarm", "GLTPillWeather",
                      "GLTPillStorage", "GLTPillQuickMessage", "[_timeFormatter stringFromDate:[NSDate date]]"):
            self.assertIn(token, text)
        for token in ('@"21:40"', '@"117 unlocks"', '@"70%"', '@"38 GB"'):
            self.assertNotIn(token, text)


if __name__ == "__main__":
    unittest.main()
