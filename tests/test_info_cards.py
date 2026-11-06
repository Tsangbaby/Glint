"""Source-contract checks, NOT UIKit execution or device acceptance.

Contracts were decoded from original Glint 1.6.3 arm64 SHA-256
 a4f0aabf448ebc50ddfaf8a2e08dcd2262ae494e01ff0756e9ab64bfa0ddc3bb.
Storage: 0x12600/0x1277c; usage: 0x17fc0; bytes: 0x1811c.
Raw instructions and the per-card evidence matrix are retained separately.
"""
import re
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "reconstructed/Sources/GLTInfoPlatters.m"


def source():
    text = SOURCE.read_text()
    return re.sub(r"//[^\n]*|/\*.*?\*/", "", text, flags=re.S)


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
            self.assertTrue(token in text, f"Missing original-backed source contract: {token}")

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


    # Original events 0xf7f4: four provider-owned rows, start AND end time.
    def test_events_original_range_limit_and_tomorrow_all_day(self):
        text = body("GLTMakeEventsPlatter")
        self.requires(text, 'MIN((NSUInteger)4,', 'events.upcomingEvents',
                      '@"%@ – %@"', 'stringFromDate:event.endDate',
                      'when = @"All day"', '@"Tomorrow, %@"',
                      'UIFontWeightSemibold', 'GLTStack(rows, 12)')
        self.assertNotIn('timeIntervalSinceNow', text)
        self.assertNotIn('constraintEqualToConstant:28', text)
        self.assertNotIn('All day ·', text)


    # Original reminders 0x100d8-0x10428: five rows; retain safe completion.
    def test_reminders_original_five_rows_and_preserved_safe_completion(self):
        text = source()
        self.requires(text, 'MIN((NSUInteger)5, events.reminders.count)',
                      'GLTStack(rows, 12)', 'configurationWithPointSize:20 weight:UIImageSymbolWeightRegular',
                      'button.tag < 0 || button.tag >= (NSInteger)_shown.count',
                      'completeReminder:reminder')
        self.assertNotIn('MIN((NSUInteger)6, events.reminders.count)', text)


    # Helpers 0xe908 / 0xe9ac / 0xfe78 / 0xff30, shared by all cards.
    def test_common_labels_original_caption_and_intrinsic_layout(self):
        self.requires(body("GLTCaption"), '[text uppercaseString]', 'alpha:0.6')
        self.requires(body("GLTLabel"), 'translatesAutoresizingMaskIntoConstraints = NO')
        self.assertNotIn('numberOfLines = 0', body("GLTLabel"))
        self.requires(body("GLTStack"), 'translatesAutoresizingMaskIntoConstraints = NO')
        self.requires(body("GLTInfoMessage"), 'numberOfLines = 0', 'alpha:0.6')


    # Weather factory 0x10ad8 and hourly block 0x11500.
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


    # Countdown 0x12e7c / 0x12d88: absolute count, title-relative phrase,
    # independent full-style target date; shared stat block at 0x1314c.
    def test_countdown_original_absolute_days_title_and_full_target_date(self):
        text = body("GLTMakeCountdownPlatter")
        self.requires(text, 'startOfDayForDate:', 'NSCalendarUnitDay',
                      'days == 1 ? @"day" : @"days", title',
                      'days == -1 ? @"day" : @"days", title',
                      'days < 0 ? -days : days', 'NSDateFormatterFullStyle',
                      'GLTInfoStatistic(', 'GLTStack(rows, 10)')
        self.requires(body("GLTInfoStatistic"), '46, UIFontWeightLight',
                      '15, UIFontWeightSemibold', 'numberOfLines = 2',
                      'if (detail)', '13, UIFontWeightRegular', 'GLTStack(rows, 2)')


    # Unlocks 0x13340 uses the same 46pt statistic, not a 34pt text stack.
    def test_unlocks_original_statistic_and_yesterday(self):
        self.requires(body("GLTMakeUnlocksPlatter"), 'GLTInfoStatistic(',
                      'unlocks.today == 1 ? @"unlock today" : @"unlocks today"',
                      '@"Yesterday: %ld"', 'unlocks.yesterday', 'GLTStack(rows, 10)')


    # Devices 0xf19c: equal-width vertical columns with distinct battery glyph.
    def test_devices_original_columns_battery_states_and_details(self):
        text = body("GLTMakeDevicePlatter")
        self.requires(text, 'GLTConnectedDevices()', 'device.glyph',
                      'constraintEqualToConstant:30', '@"battery.100.bolt"',
                      '@"battery.25"', '@"battery.50"', '@"battery.75"', '@"battery.100"',
                      'device.percent <= 20', 'device.percent <= 60', 'device.percent <= 85',
                      'systemRedColor', 'systemGreenColor', 'monospacedDigitSystemFontOfSize:11',
                      'name.numberOfLines = 2', 'details.numberOfLines = 2',
                      'UIStackViewDistributionFillEqually', 'GLTStack(parts, 6)')
        self.assertNotIn('GLTCaption(@"Devices")', text)


    # Notification 0x10640: 36pt icon beside app/title/four-line message.
    def test_notifications_original_icon_text_column_and_message_limit(self):
        text = body("GLTMakeNotificationPlatter")
        self.requires(text, 'constraintEqualToConstant:36', 'title.hidden = notification.title.length == 0',
                      'message.numberOfLines = 4', '16, UIFontWeightSemibold',
                      '15, UIFontWeightRegular', 'GLTStack(@[app, title, message], 3)',
                      '@[icon, text]', 'row.spacing = 12', 'UIStackViewAlignmentTop',
                      '@selector(open)')
        self.assertNotIn('if (notification.message.length)', text)
        self.requires(source(), '[self.notification open]', '[self close]')


    # Original weather glyph helper 0x1b698 passes SF Symbol weight 6,
    # not UIFontWeightRegular (a floating-point font weight / zero).
    def test_weather_symbols_use_original_semibold_symbol_enum(self):
        self.requires(body("GLTMakeWeatherPlatter"),
                      '30, UIImageSymbolWeightSemibold', '18, UIImageSymbolWeightSemibold')


if __name__ == "__main__":
    unittest.main()
