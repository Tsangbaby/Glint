"""Retained original-bound card contracts and explicit beta1 removal checks.

Source/static checks, NOT UIKit execution or device acceptance.
Original Glint 1.6.3 arm64 SHA256
 a4f0aabf448ebc50ddfaf8a2e08dcd2262ae494e01ff0756e9ab64bfa0ddc3bb.
Storage 0x12600/0x1277c; usage 0x17fc0; weather 0x10ad8; notification 0x10640.
"""
import re
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "reconstructed/Sources/GLTInfoPlatters.m"


def source():
    text = SOURCE.read_text()
    text = re.sub(r"//[^\n]*|/\*.*?\*/", "", text, flags=re.S)
    # Presentation/geometry contracts stay independent of localization wrapping;
    # test_runtime_localization checks that every runtime label is actually wrapped.
    return re.sub(r'GLTLocalizedString\((@"(?:\\.|[^"\\])*")\)', r'\1', text)


def body(name):
    text = source()
    start = text.find(name + "(")
    if start < 0:
        return ""
    start = text.find("{", start)
    depth = 1
    pos = start + 1
    while depth and pos < len(text):
        depth += (text[pos] == "{") - (text[pos] == "}")
        pos += 1
    return text[start + 1:pos - 1]


class InfoCardsContracts(unittest.TestCase):
    def requires(self, text, *tokens):
        for token in tokens:
            self.assertIn(token, text, f"Missing retained original-backed contract: {token}")

    def test_storage_memory_original_usage_and_two_meter_rows(self):
        self.requires(body("GLTInfoCurrentSystemUsage"),
                      'attributesOfFileSystemForPath:@"/private/var"',
                      'NSFileSystemFreeSize', 'NSFileSystemSize',
                      'host_page_size(', 'host_statistics64(', 'HOST_VM_INFO64',
                      'stats.free_count + stats.inactive_count + stats.purgeable_count',
                      'physicalMemory', 'KERN_SUCCESS')
        self.requires(body("GLTInfoUsageRow"), '@"%@ free of %@"',
                      'NSByteCountFormatterCountStyleFile',
                      'total - free', '(double)total', 'total > 0',
                      'MAX(0.001, used)', 'MIN(1.0,',
                      'constraintEqualToConstant:6', 'cornerRadius = 3',
                      'constraintEqualToAnchor:track.widthAnchor multiplier:',
                      'GLTStack(@[header, track], 8)')
        self.requires(body("GLTMakeStoragePlatter"),
                      'GLTInfoCurrentSystemUsage()', '@"Storage", @"internaldrive.fill"',
                      '@"Memory", @"memorychip.fill"', 'systemBlueColor',
                      'systemPurpleColor', 'GLTStack(@[storage, memory], 18)')

    def test_common_labels_original_caption_and_intrinsic_layout(self):
        self.requires(body("GLTCaption"), '[text uppercaseString]', 'alpha:0.6')
        self.requires(body("GLTLabel"), 'translatesAutoresizingMaskIntoConstraints = NO')
        self.assertNotIn('numberOfLines = 0', body("GLTLabel"))
        self.requires(body("GLTStack"), 'translatesAutoresizingMaskIntoConstraints = NO')
        self.requires(body("GLTInfoMessage"), 'numberOfLines = 0', 'alpha:0.6')

    def test_weather_original_feels_like_sun_times_and_hourly_contract(self):
        text = body("GLTMakeWeatherPlatter")
        self.requires(text, 'GLTCaption(@"Weather")', '@"Loading the weather…"',
                      'weather.feelsLike', '@"Feels like %@ · Rain %ld%%"',
                      'weather.sunrises.firstObject', 'weather.sunsets.firstObject',
                      '@"Sunrise %@ · Sunset %@"', 'if (sunrise && sunset)',
                      'GLTLabel(place, 17, UIFontWeightSemibold',
                      '46, UIFontWeightLight', '@"Now"',
                      'constraintEqualToConstant:26', 'UIStackViewDistributionFillEqually',
                      'GLTStack(@[headline, strip, attribution], 14)',
                      'setCustomSpacing:8 afterView:strip')
        self.assertNotIn('hours.count >=', text)
        self.assertNotIn('weather.rainChance > 0', text)

    def test_notifications_original_icon_text_column_and_message_limit(self):
        text = body("GLTMakeNotificationPlatter")
        self.requires(text, 'constraintEqualToConstant:36', 'title.hidden = notification.title.length == 0',
                      'message.numberOfLines = 4', '16, UIFontWeightSemibold',
                      '15, UIFontWeightRegular', 'GLTStack(@[app, title, message], 3)',
                      '@[icon, text]', 'row.spacing = 12', 'UIStackViewAlignmentTop', '@selector(open)')
        self.assertNotIn('if (notification.message.length)', text)
        self.requires(source(), '[self.notification open]', '[self close]')

    def test_weather_symbols_use_original_semibold_symbol_enum(self):
        self.requires(body("GLTMakeWeatherPlatter"),
                      '30, UIImageSymbolWeightSemibold', '18, UIImageSymbolWeightSemibold')

    def test_removed_card_factories_and_their_unique_statistic_helpers_are_absent(self):
        text = SOURCE.read_text()
        for obsolete in ("GLTMakeEventsPlatter", "GLTRemindersPlatterView", "GLTMakeRemindersPlatter",
                         "GLTMakeCountdownPlatter", "GLTMakeUnlocksPlatter", "GLTMakeDevicePlatter",
                         "GLTInfoStatistic", "GLTConnectedDevices", "completeReminder:",
                         "EKEvent", "EKReminder", "countdownTitle", "countdownDate", "GLTUnlocks"):
            self.assertNotIn(obsolete, text)
        # Sunrise/sunset measurements remain part of the retained weather detail,
        # not a resurrected standalone Sunrise & Sunset pill.
        self.assertIn("weather.sunrises.firstObject", text)
        self.assertIn("weather.sunsets.firstObject", text)


if __name__ == "__main__":
    unittest.main()
