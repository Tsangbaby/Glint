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
    GLTPrefs *prefs = [GLTPrefs sharedPrefs];

    if (!force && _updated && -[_updated timeIntervalSinceNow] < kGLTRefreshInterval) {
        return;
    }
    if (_loading) return;
    _loading = YES;

    NSString *city = prefs.weatherCity;
    if (city.length) {
        [_geocoder geocodeAddressString:city completionHandler:^(NSArray<CLPlacemark *> *placemarks,
                                                                 NSError *error) {
            CLPlacemark *mark = placemarks.firstObject;
            if (!mark.location) {
                [self failWithProblem:[NSString stringWithFormat:@"Glint can't find \"%@\".", city]];
                return;
            }
            [self fetchForLocation:mark.location place:mark.locality ?: city];
        }];
        return;
    }

#if GLINT_VERIFICATION_BUILD
    [self failWithProblem:@"Set a city in Glint's settings for this verification build."];
    return;
#else
    CLAuthorizationStatus status = _locationManager.authorizationStatus;
    if (status != kCLAuthorizationStatusAuthorizedAlways &&
        status != kCLAuthorizationStatusAuthorizedWhenInUse) {
        [self failWithProblem:@"Location is not authorized. Type a city in Glint's settings."];
        return;
    }
    [_locationManager requestLocation];
#endif
}

- (void)failWithProblem:(NSString *)problem {
    _loading = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.problem = problem;
        self.hasData = NO;
        self->_updated = [NSDate date];
        [[NSNotificationCenter defaultCenter] postNotificationName:GLTSourcesDidChangeNotification
                                                            object:nil];
    });
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
    CLLocation *location = locations.lastObject;
    if (!location) return;

    [_geocoder reverseGeocodeLocation:location completionHandler:^(NSArray<CLPlacemark *> *placemarks,
                                                                  NSError *error) {
        CLPlacemark *mark = placemarks.firstObject;
        [self fetchForLocation:location place:mark.locality];
    }];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    [self failWithProblem:@"Glint can't find where you are. Type a city in Glint's settings."];
}

#pragma mark - Networking

- (void)fetchForLocation:(CLLocation *)location place:(NSString *)place {
    NSString *url = [NSString stringWithFormat:kGLTForecastURL,
                     location.coordinate.latitude, location.coordinate.longitude];

    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:url]
                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            [self failWithProblem:@"The weather isn't available right now."];
            return;
        }

        NSError *jsonError = nil;
        id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (![payload isKindOfClass:[NSDictionary class]] || ![payload objectForKeyedSubscript:@"current"]) {
            [self failWithProblem:@"The weather isn't available right now."];
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self applyForecast:payload place:place];
        });
    }] resume];
}

#pragma mark - Parsing

- (void)applyForecast:(NSDictionary *)payload place:(NSString *)place {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm";

    NSInteger offset = [payload[@"utc_offset_seconds"] integerValue];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:offset];

    NSDictionary *current = payload[@"current"];
    NSDictionary *daily   = payload[@"daily"];
    NSDictionary *hourly  = payload[@"hourly"];

    if (![current isKindOfClass:[NSDictionary class]]) {
        [self failWithProblem:@"The weather isn't available right now."];
        return;
    }

    _temperature = [current[@"temperature_2m"] doubleValue];
    _feelsLike   = [current[@"apparent_temperature"] doubleValue];
    _code        = [current[@"weather_code"] integerValue];
    _isDay       = [current[@"is_day"] boolValue];

    if ([daily isKindOfClass:[NSDictionary class]]) {
        _high       = [daily[@"temperature_2m_max"] firstObject] ? [daily[@"temperature_2m_max"][0] doubleValue] : 0;
        _low        = [daily[@"temperature_2m_min"] firstObject] ? [daily[@"temperature_2m_min"][0] doubleValue] : 0;
        _rainChance = [daily[@"precipitation_probability_max"] firstObject]
            ? [daily[@"precipitation_probability_max"][0] integerValue] : 0;

        NSMutableArray<NSDate *> *sunrises = [NSMutableArray array];
        NSMutableArray<NSDate *> *sunsets  = [NSMutableArray array];
        for (NSString *text in daily[@"sunrise"]) {
            NSDate *date = [formatter dateFromString:text];
            if (date) [sunrises addObject:date];
        }
        for (NSString *text in daily[@"sunset"]) {
            NSDate *date = [formatter dateFromString:text];
            if (date) [sunsets addObject:date];
        }
        _sunrises = sunrises;
        _sunsets  = sunsets;
    }

    if ([hourly isKindOfClass:[NSDictionary class]]) {
        NSArray *times        = hourly[@"time"];
        NSArray *temperatures = hourly[@"temperature_2m"];
        NSArray *codes        = hourly[@"weather_code"];
        NSArray *dayFlags     = hourly[@"is_day"];

        NSDate *now = [NSDate date];
        NSMutableArray<GLTWeatherHour *> *hours = [NSMutableArray array];

        for (NSUInteger i = 0; i < times.count && i < temperatures.count; i++) {
            NSDate *date = [formatter dateFromString:times[i]];
            if (!date || [date compare:now] == NSOrderedAscending) continue;

            GLTWeatherHour *hour = [GLTWeatherHour new];
            hour.date = date;
            hour.temperature = [temperatures[i] doubleValue];
            hour.code = i < codes.count ? [codes[i] integerValue] : 0;
            hour.isDay = i < dayFlags.count ? [dayFlags[i] boolValue] : YES;
            [hours addObject:hour];
            if (hours.count >= 24) break;
        }
        _hours = hours;
    }

    _place    = place;
    _problem  = nil;
    _hasData  = YES;
    _loading  = NO;
    _updated  = [NSDate date];
    _lastCity = place;

    [[NSNotificationCenter defaultCenter] postNotificationName:GLTSourcesDidChangeNotification
                                                        object:nil];
}

#pragma mark - Sun

// Earliest sunrise/sunset still ahead of now, across the two forecast days.
- (NSDate *)nextSunEvent:(BOOL *)isSunset {
    NSDate *best = nil;
    BOOL bestIsSunset = NO;

    for (NSDate *date in _sunrises) {
        if ([date timeIntervalSinceNow] <= 0) continue;
        if (!best || [date compare:best] == NSOrderedAscending) {
            best = date;
            bestIsSunset = NO;
        }
    }
    for (NSDate *date in _sunsets) {
        if ([date timeIntervalSinceNow] <= 0) continue;
        if (!best || [date compare:best] == NSOrderedAscending) {
            best = date;
            bestIsSunset = YES;
        }
    }

    if (isSunset) *isSunset = bestIsSunset;
    return best;
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
    if (code == 0) return @"Clear";
    if (code == 1) return @"Mostly Clear";
    if (code == 2) return @"Partly Cloudy";
    if (code == 3) return @"Cloudy";
    if (code == 45 || code == 48) return @"Fog";
    if (code >= 51 && code <= 55) return @"Drizzle";
    if (code == 56 || code == 57) return @"Freezing Rain";
    if (code == 61 || code == 63) return @"Rain";
    if (code == 65) return @"Heavy Rain";
    if (code == 66 || code == 67) return @"Freezing Rain";
    if (code >= 71 && code <= 77) return @"Snow";
    if (code >= 80 && code <= 82) return @"Showers";
    if (code == 85 || code == 86) return @"Snow";
    if (code >= 95 && code <= 99) return @"Thunderstorms";
    return @"Cloudy";
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
