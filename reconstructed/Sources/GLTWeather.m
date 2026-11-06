//
//  GLTWeather.m
//
//  Open-Meteo client. Two sources of location: the coarser CoreLocation fix
//  (~1 km, requested only when no city is configured) or a geocoded city name
//  from the preference bundle.
//
//  Recovered from 0x19dec…0x1b614 + 0x1b698 (symbol configuration).
//

#import "Glint.h"
#import "GLTLocalization.h"
#import <math.h>

// The endpoint is fixed; only the coordinates change. `forecast_days=2` covers
// "today + tomorrow", which is as far ahead as the card looks.
static NSString *const kGLTForecastURL =
    @"https://api.open-meteo.com/v1/forecast?latitude=%.2f&longitude=%.2f"
    @"&current=temperature_2m,apparent_temperature,weather_code,is_day"
    @"&hourly=temperature_2m,weather_code,is_day"
    @"&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"
    @"&timezone=auto&forecast_days=2";

// Refreshes are cheap but not free; the original throttles unforced calls.
static const NSTimeInterval kGLTRefreshInterval = 15 * 60;
// A failed request is not fresh weather. Back off ticks without hiding retries
// for the full successful-forecast cache interval.
static const NSTimeInterval kGLTRetryInterval = 60;

static BOOL GLTWeatherNumber(id value) {
    return [value isKindOfClass:[NSNumber class]] && isfinite([value doubleValue]);
}

static NSArray *GLTWeatherArray(id value) {
    return [value isKindOfClass:[NSArray class]] ? value : @[];
}

static NSDictionary *GLTWeatherDictionary(id value) {
    return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}

@interface GLTWeather () <CLLocationManagerDelegate>
@property (nonatomic, readwrite) BOOL hasData;
@property (nonatomic, readwrite) NSString *problem;
@property (nonatomic, readwrite) NSString *place;
@property (nonatomic, readwrite) double temperature;
@property (nonatomic, readwrite) double feelsLike;
@property (nonatomic, readwrite) double high;
@property (nonatomic, readwrite) double low;
@property (nonatomic, readwrite) long long rainChance;
@property (nonatomic, readwrite) long long code;
@property (nonatomic, readwrite) BOOL isDay;
@property (nonatomic, readwrite) NSArray *hours;
@property (nonatomic, readwrite) NSArray *sunrises;
@property (nonatomic, readwrite) NSArray *sunsets;
- (BOOL)finishObsoleteRequest;
@end

@implementation GLTWeather

+ (GLTWeather *)sharedWeather {
    static GLTWeather *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [GLTWeather new]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    _locationManager = [CLLocationManager new];
    _locationManager.delegate = self;
    _locationManager.desiredAccuracy = kCLLocationAccuracyKilometer;

    _geocoder = [CLGeocoder new];
    _hours = @[];
    _sunrises = @[];
    _sunsets = @[];
    return self;
}

#pragma mark - Refresh

- (void)refreshForcing:(BOOL)force {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self refreshForcing:force]; });
        return;
    }
    GLTPrefs *prefs = [GLTPrefs sharedPrefs];
    NSString *city = prefs.weatherCity ?: @"";
    BOOL sameCity = [(_lastCity ?: @"") isEqualToString:city];
    if (_loading) return;
    if (!force && sameCity) {
        if (_hasData && _updated && -[_updated timeIntervalSinceNow] < kGLTRefreshInterval) return;
        if (_attempted && -[_attempted timeIntervalSinceNow] < kGLTRetryInterval) return;
    }
    _loading = YES;
    _lastCity = [city copy];
    _attempted = [NSDate date];
    _problem = nil;
    if (!sameCity) _hasData = NO;

    if (city.length) {
        [_geocoder geocodeAddressString:city completionHandler:^(NSArray<CLPlacemark *> *placemarks,
                                                                 NSError *error) {
            if ([self finishObsoleteRequest]) return;
            CLPlacemark *mark = placemarks.firstObject;
            if (error || !mark.location) {
                [self failWithProblem:[NSString stringWithFormat:GLTLocalizedString(@"Glint can't find \"%@\"."), city]];
                return;
            }
            [self fetchForLocation:mark.location place:mark.locality ?: city];
        }];
        return;
    }

    // Read existing host authorization only; never prompt or change host permissions.
    CLAuthorizationStatus status = _locationManager.authorizationStatus;
    if (status != kCLAuthorizationStatusAuthorizedAlways &&
        status != kCLAuthorizationStatusAuthorizedWhenInUse) {
        [self failWithProblem:GLTLocalizedString(@"Location is not authorized. Type a city in Glint's settings.")];
        return;
    }
    [_locationManager requestLocation];
}

- (void)failWithProblem:(NSString *)problem {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self finishObsoleteRequest]) return;
        self->_loading = NO;
        self->_attempted = [NSDate date];
        self.problem = problem;
        self.hasData = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:GLTSourcesDidChangeNotification
                                                            object:self];
    });
}

// Preferences may change while geocoding, locating or fetching. Never publish
// the old city's result as the new city's cached forecast.
- (BOOL)finishObsoleteRequest {
    NSString *city = [GLTPrefs sharedPrefs].weatherCity ?: @"";
    if ([(_lastCity ?: @"") isEqualToString:city]) return NO;
    _loading = NO;
    [self refreshForcing:YES];
    return YES;
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    CLAuthorizationStatus status = manager.authorizationStatus;
    if (status == kCLAuthorizationStatusAuthorizedWhenInUse ||
        status == kCLAuthorizationStatusAuthorizedAlways) {
        [self refreshForcing:YES];
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    if ([self finishObsoleteRequest] || !_loading) return;
    if ([GLTPrefs sharedPrefs].weatherCity.length) return;
    CLLocation *location = locations.lastObject;
    if (!location || location.horizontalAccuracy < 0) {
        [self failWithProblem:GLTLocalizedString(@"Glint can't find where you are. Type a city in Glint's settings.")];
        return;
    }

    [_geocoder reverseGeocodeLocation:location completionHandler:^(NSArray<CLPlacemark *> *placemarks,
                                                                  NSError *error) {
        if ([self finishObsoleteRequest]) return;
        CLPlacemark *mark = placemarks.firstObject;
        [self fetchForLocation:location place:mark.locality];
    }];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    if ([self finishObsoleteRequest] || !_loading || [GLTPrefs sharedPrefs].weatherCity.length) return;
    [self failWithProblem:GLTLocalizedString(@"Glint can't find where you are. Type a city in Glint's settings.")];
}

#pragma mark - Networking

- (void)fetchForLocation:(CLLocation *)location place:(NSString *)place {
    if (!location || !CLLocationCoordinate2DIsValid(location.coordinate)) {
        [self failWithProblem:GLTLocalizedString(@"Glint can't find where you are. Type a city in Glint's settings.")];
        return;
    }
    NSString *url = [NSString stringWithFormat:kGLTForecastURL,
                     location.coordinate.latitude, location.coordinate.longitude];

    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:url]
                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger statusCode = [response isKindOfClass:[NSHTTPURLResponse class]]
            ? [(NSHTTPURLResponse *)response statusCode] : 0;
        if (error || !data.length || statusCode < 200 || statusCode >= 300) {
            [self failWithProblem:GLTLocalizedString(@"The weather isn't available right now.")];
            return;
        }

        NSError *jsonError = nil;
        id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || ![payload isKindOfClass:[NSDictionary class]]) {
            [self failWithProblem:GLTLocalizedString(@"The weather isn't available right now.")];
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self applyForecast:payload place:place];
        });
    }] resume];
}

#pragma mark - Parsing

- (void)applyForecast:(NSDictionary *)payload place:(NSString *)place {
    if ([self finishObsoleteRequest]) return;
    if (![payload isKindOfClass:[NSDictionary class]] || payload[@"error"]) {
        [self failWithProblem:GLTLocalizedString(@"The weather isn't available right now.")];
        return;
    }
    NSDictionary *current = GLTWeatherDictionary(payload[@"current"]);
    NSDictionary *daily = GLTWeatherDictionary(payload[@"daily"]);
    NSDictionary *hourly = GLTWeatherDictionary(payload[@"hourly"]);
    NSArray *highs = GLTWeatherArray(daily[@"temperature_2m_max"]);
    NSArray *lows = GLTWeatherArray(daily[@"temperature_2m_min"]);
    NSArray *rain = GLTWeatherArray(daily[@"precipitation_probability_max"]);
    if (!GLTWeatherNumber(payload[@"utc_offset_seconds"]) ||
        !GLTWeatherNumber(current[@"temperature_2m"]) ||
        !GLTWeatherNumber(current[@"apparent_temperature"]) ||
        !GLTWeatherNumber(current[@"weather_code"]) ||
        !GLTWeatherNumber(current[@"is_day"]) ||
        !GLTWeatherNumber(highs.firstObject) || !GLTWeatherNumber(lows.firstObject) ||
        !GLTWeatherNumber(rain.firstObject)) {
        [self failWithProblem:GLTLocalizedString(@"The weather isn't available right now.")];
        return;
    }
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm";

    NSInteger offset = [payload[@"utc_offset_seconds"] integerValue];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:offset];

    _temperature = [current[@"temperature_2m"] doubleValue];
    _feelsLike   = [current[@"apparent_temperature"] doubleValue];
    _code        = [current[@"weather_code"] integerValue];
    _isDay       = [current[@"is_day"] boolValue];

    _high = [highs.firstObject doubleValue];
    _low = [lows.firstObject doubleValue];
    _rainChance = [rain.firstObject integerValue];

    NSMutableArray<NSDate *> *sunrises = [NSMutableArray array];
    NSMutableArray<NSDate *> *sunsets = [NSMutableArray array];
    for (id text in GLTWeatherArray(daily[@"sunrise"])) {
        if (![text isKindOfClass:[NSString class]]) continue;
        NSDate *date = [formatter dateFromString:text];
        if (date) [sunrises addObject:date];
    }
    for (id text in GLTWeatherArray(daily[@"sunset"])) {
        if (![text isKindOfClass:[NSString class]]) continue;
        NSDate *date = [formatter dateFromString:text];
        if (date) [sunsets addObject:date];
    }
    _sunrises = sunrises;
    _sunsets = sunsets;

    NSArray *times = GLTWeatherArray(hourly[@"time"]);
    NSArray *temperatures = GLTWeatherArray(hourly[@"temperature_2m"]);
    NSArray *codes = GLTWeatherArray(hourly[@"weather_code"]);
    NSArray *dayFlags = GLTWeatherArray(hourly[@"is_day"]);
    // Original 0x1aab8 / 0x1aaec: include the current hour; seven columns.
    NSDate *earliest = [NSDate dateWithTimeIntervalSinceNow:-3600];
    NSMutableArray<GLTWeatherHour *> *hours = [NSMutableArray array];
    NSUInteger count = MIN(MIN(times.count, temperatures.count), MIN(codes.count, dayFlags.count));
    for (NSUInteger i = 0; i < count; i++) {
        if (![times[i] isKindOfClass:[NSString class]] || !GLTWeatherNumber(temperatures[i]) ||
            !GLTWeatherNumber(codes[i]) || !GLTWeatherNumber(dayFlags[i])) continue;
        NSDate *date = [formatter dateFromString:times[i]];
        if (!date || [date compare:earliest] == NSOrderedAscending) continue;
        GLTWeatherHour *hour = [GLTWeatherHour new];
        hour.date = date;
        hour.temperature = [temperatures[i] doubleValue];
        hour.code = [codes[i] integerValue];
        hour.isDay = [dayFlags[i] boolValue];
        [hours addObject:hour];
        if (hours.count >= 7) break;
    }
    _hours = hours;

    _place    = place;
    _problem  = nil;
    _hasData  = YES;
    _loading  = NO;
    _updated  = [NSDate date];


    [[NSNotificationCenter defaultCenter] postNotificationName:GLTSourcesDidChangeNotification
                                                        object:self];
}

#pragma mark - WMO code mapping

+ (NSString *)symbolForCode:(NSInteger)code isDay:(BOOL)isDay {
    NSString *day   = isDay ? @"sun.max.fill" : @"moon.stars.fill";
    NSString *cloud = isDay ? @"cloud.sun.fill" : @"cloud.moon.fill";

    if (code == 0) return day;
    if (code == 1) return day;
    if (code == 2) return cloud;
    if (code == 3) return @"cloud.fill";
    if (code == 45 || code == 48) return @"cloud.fog.fill";
    if (code >= 51 && code <= 55) return @"cloud.drizzle.fill";
    if (code == 56 || code == 57) return @"cloud.sleet.fill";
    if (code == 61 || code == 63) return @"cloud.rain.fill";
    if (code == 65) return @"cloud.heavyrain.fill";
    if (code == 66 || code == 67) return @"cloud.sleet.fill";
    if (code >= 71 && code <= 77) return @"cloud.snow.fill";
    if (code >= 80 && code <= 82) return @"cloud.heavyrain.fill";
    if (code == 85 || code == 86) return @"cloud.snow.fill";
    if (code >= 95 && code <= 99) return @"cloud.bolt.rain.fill";
    return cloud;
}

+ (NSString *)descriptionForCode:(NSInteger)code {
    if (code == 0) return GLTLocalizedString(@"Clear");
    if (code == 1) return GLTLocalizedString(@"Mostly Clear");
    if (code == 2) return GLTLocalizedString(@"Partly Cloudy");
    if (code == 3) return GLTLocalizedString(@"Cloudy");
    if (code == 45 || code == 48) return GLTLocalizedString(@"Fog");
    if (code >= 51 && code <= 55) return GLTLocalizedString(@"Drizzle");
    if (code == 56 || code == 57) return GLTLocalizedString(@"Freezing Rain");
    if (code == 61 || code == 63) return GLTLocalizedString(@"Rain");
    if (code == 65) return GLTLocalizedString(@"Heavy Rain");
    if (code == 66 || code == 67) return GLTLocalizedString(@"Freezing Rain");
    if (code >= 71 && code <= 77) return GLTLocalizedString(@"Snow");
    if (code >= 80 && code <= 82) return GLTLocalizedString(@"Showers");
    if (code == 85 || code == 86) return GLTLocalizedString(@"Snow");
    if (code >= 95 && code <= 99) return GLTLocalizedString(@"Thunderstorms");
    return GLTLocalizedString(@"Cloudy");
}

// Temperature honours the device's unit preference.
+ (NSString *)temperatureString:(double)celsius {
    NSMeasurement *measurement =
        [[NSMeasurement alloc] initWithDoubleValue:celsius unit:NSUnitTemperature.celsius];
    NSMeasurementFormatter *formatter = [NSMeasurementFormatter new];
    formatter.unitStyle = NSFormattingUnitStyleShort;
    formatter.unitOptions = NSMeasurementFormatterUnitOptionsProvidedUnit;
    [formatter.numberFormatter setMaximumFractionDigits:0];
    return [formatter stringFromMeasurement:measurement];
}

@end
