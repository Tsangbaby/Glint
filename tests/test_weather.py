"""Weather regressions: source boundaries on Linux; real Foundation replay on Darwin.

These checks do not establish CoreLocation, SpringBoard rendering or handset network
availability. Original arm64 methods: refresh 0x19ea0, fetch 0x1a46c, parse 0x1a770.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "reconstructed/Sources/GLTWeather.m"
HEADER = ROOT / "reconstructed/Headers/GLTWeather.h"


def method(signature):
    text = SOURCE.read_text()
    start = text.index(signature)
    start = text.index("{", start)
    depth, end = 1, start + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start + 1:end - 1]


class WeatherLocationContracts(unittest.TestCase):
    def test_verification_build_can_read_existing_location_authorization(self):
        text = method("- (void)refreshForcing:")
        self.assertNotIn("#if GLINT_VERIFICATION_BUILD", text,
                         "verification build currently blocks even already-authorized location")
        city = text.index("geocodeAddressString:city")
        status = text.index("authorizationStatus")
        request = text.index("requestLocation")
        self.assertLess(city, status, "configured city must not require location permission")
        self.assertLess(status, request)
        self.assertIn("kCLAuthorizationStatusAuthorizedAlways", text)
        self.assertIn("kCLAuthorizationStatusAuthorizedWhenInUse", text)
        self.assertNotRegex(SOURCE.read_text(), r"setAuthorizationStatusByType:|requestAlwaysAuthorization|requestWhenInUseAuthorization")
        self.assertNotIn("CLLoc...ager", HEADER.read_text() + SOURCE.read_text())


class WeatherRefreshContracts(unittest.TestCase):
    def test_city_changes_bypass_success_cache_and_failures_only_back_off_briefly(self):
        refresh = method("- (void)refreshForcing:")
        failure = method("- (void)failWithProblem:")
        apply = method("- (void)applyForecast:")
        self.assertIn("sameCity", refresh,
                      "15-minute cache currently ignores configured-city changes")
        self.assertIn("isEqualToString:city", refresh)
        self.assertIn("_hasData && _updated", refresh)
        self.assertIn("kGLTRetryInterval", refresh)
        self.assertIn("_attempted", refresh)
        self.assertIn("_lastCity = [city copy]", refresh)
        self.assertNotIn("_lastCity = place", apply)
        self.assertNotIn("_updated =", failure,
                         "a failed fetch must not become a fresh 15-minute forecast")
        self.assertIn("self->_loading = NO", failure)
        self.assertIn("dispatch_async(dispatch_get_main_queue()", failure)
        self.assertIn("object:self", failure)
        self.assertIn("object:self", apply)
        self.assertIn("finishObsoleteRequest", failure)
        self.assertIn("failWithProblem:", method("- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:"))


class WeatherForecastContracts(unittest.TestCase):
    def test_response_validation_and_original_seven_current_hour_columns(self):
        fetch = method("- (void)fetchForLocation:")
        apply = method("- (void)applyForecast:")
        self.assertIn("NSHTTPURLResponse", fetch,
                      "an HTTP/provider error must not be interpreted as a forecast")
        self.assertIn("statusCode", fetch)
        self.assertIn("jsonError", fetch)
        self.assertIn("GLTWeatherNumber", apply)
        self.assertIn("GLTWeatherArray", apply)
        self.assertIn("payload[@\"error\"]", apply)
        self.assertIn("dateWithTimeIntervalSinceNow:-3600", apply,
                      "original 0x1aab8 includes the current hour, not only future hours")
        self.assertIn("hours.count >= 7", apply,
                      "original 0x1aaec stops at seven columns")
        self.assertIn("isKindOfClass:[NSString class]", apply)
        self.assertNotIn("nextSunEvent:", SOURCE.read_text() + HEADER.read_text())
        self.assertIn("_sunrises =", apply)
        self.assertIn("_sunsets", apply)
        description = method("+ (NSString *)descriptionForCode:")
        self.assertNotRegex(description, r'return @"', "fixed weather conditions must use runtime localization")


@unittest.skipUnless(__import__("sys").platform == "darwin", "requires real Apple Foundation; not a fake Linux SDK")
class WeatherFoundationReplay(unittest.TestCase):
    def test_actual_forecast_method_on_valid_partial_null_and_provider_error_json(self):
        import os
        import subprocess
        import tempfile
        source = SOURCE.read_text()
        # Extract the exact production parser and numeric/container helpers.
        helpers = source[source.index("static BOOL GLTWeatherNumber"):source.index("@interface GLTWeather")]
        header = HEADER.read_text()
        interface = header[header.index("@interface"):header.index("#pragma mark - class methods")] + "@end\n"
        hour = (ROOT / "reconstructed/Headers/GLTWeatherHour.h").read_text()
        hour = hour[hour.index("@interface"):hour.index("@end") + 4]
        program = r'''#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <math.h>
@class CLLocationManager, CLGeocoder;
NSString *GLTLocalizedString(NSString *s) { return s; }
NSString *const GLTSourcesDidChangeNotification = @"host.weather.changed";
''' + helpers + hour + "\n@implementation GLTWeatherHour\n@end\n" + interface + r'''
@interface GLTWeather ()
@property(nonatomic, readwrite) BOOL hasData;
@property(nonatomic, strong, readwrite) NSString *problem;
- (BOOL)finishObsoleteRequest;
- (void)applyForecast:(NSDictionary *)payload place:(NSString *)place;
- (void)failWithProblem:(NSString *)problem;
@end
@implementation GLTWeather
// Explicit settings-boundary double: city does not change during this parser replay.
- (BOOL)finishObsoleteRequest { return NO; }
- (void)failWithProblem:(NSString *)problem {
''' + method("- (void)failWithProblem:") + "\n}\n- (void)applyForecast:(NSDictionary *)payload place:(NSString *)place {\n" + method("- (void)applyForecast:") + r'''
}
@end
static void check(BOOL pass, NSString *name) { if (!pass) { NSLog(@"FAIL %@", name); exit(1); } }
static void drain(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]]; }
int main(void) { @autoreleasepool {
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"yyyy-MM-dd'T'HH:mm";
    f.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSMutableArray *times = [NSMutableArray array], *values = [NSMutableArray array];
    for (NSInteger i = 0; i < 24; i++) {
        [times addObject:[f stringFromDate:[NSDate dateWithTimeIntervalSinceNow:(i - 0.5) * 3600]]];
        [values addObject:@12];
    }
    NSDictionary *daily = @{@"temperature_2m_max":@[@15], @"temperature_2m_min":@[@7],
      @"precipitation_probability_max":@[@30], @"sunrise":@[times[0]], @"sunset":@[times[1]]};
    NSMutableDictionary *payload = [@{@"utc_offset_seconds":@0,
      @"current":@{@"temperature_2m":@12, @"apparent_temperature":@11, @"weather_code":@2, @"is_day":@1},
      @"daily":daily, @"hourly":@{@"time":times, @"temperature_2m":values,
      @"weather_code":values, @"is_day":values}} mutableCopy];
    GLTWeather *w = [GLTWeather new];
    [w applyForecast:payload place:@"Reference"];
    check(w.hasData && w.temperature == 12 && w.high == 15 && w.low == 7, @"valid current/daily");
    check(w.hours.count == 7, @"seven columns");
    check([[(GLTWeatherHour *)w.hours.firstObject date] timeIntervalSinceNow] < 0, @"includes current hour");
    NSDate *success = [w valueForKey:@"updated"];
    payload[@"hourly"] = @{@"time":@[[NSNull null], times[1]], @"temperature_2m":@[[NSNull null], @13],
                          @"weather_code":@[@0], @"is_day":@[@1]};
    payload[@"daily"] = @{@"temperature_2m_max":@[@15], @"temperature_2m_min":@[@7],
      @"precipitation_probability_max":@[@30], @"sunrise":@[[NSNull null]], @"sunset":@"wrong type"};
    [w applyForecast:payload place:@"Reference"];
    check(w.hasData && w.hours.count == 0 && w.sunrises.count == 0 && w.sunsets.count == 0, @"malformed optional rows cleared");
    success = [w valueForKey:@"updated"];
    for (id invalid in @[@{@"error":@YES, @"reason":@"provider error"}, @{@"current":[NSNull null]},
                        @{@"current":@{@"temperature_2m":[NSNull null]}}, @[]]) {
        [w setValue:@YES forKey:@"loading"];
        [w applyForecast:invalid place:@"Reference"];
        drain();
        check(!w.hasData && w.problem.length && ![[w valueForKey:@"loading"] boolValue], @"invalid forecast terminates loading");
        check([[w valueForKey:@"updated"] isEqual:success], @"failure does not refresh cache");
    }
    puts("GLINT_WEATHER_FOUNDATION_PASS");
} return 0; }
'''
        scratch = Path(os.environ.get("TMPDIR", Path.home() / ".hermes/cache/scratch"))
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="glint-weather-", dir=scratch) as temp:
            path = Path(temp)
            (path / "weather.m").write_text(program)
            compiled = subprocess.run(["clang", "-fobjc-arc", "-fblocks", "-framework", "Foundation",
                                       str(path / "weather.m"), "-o", str(path / "weather")], capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            replay = subprocess.run([str(path / "weather")], capture_output=True, text=True, timeout=15)
            self.assertEqual(replay.returncode, 0, replay.stdout + replay.stderr)
            self.assertIn("GLINT_WEATHER_FOUNDATION_PASS", replay.stdout)


if __name__ == "__main__":
    unittest.main()
