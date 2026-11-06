//
//  GLTWeather.h
//  Glint (reconstructed interface)
//
//  Recovered from ObjC metadata of Glint.dylib 1.6.3
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreLocation/CoreLocation.h>


@interface GLTWeather : NSObject
{
    CLLocationManager *            _locationManager; // 0x08
    CLGeocoder *                   _geocoder; // 0x10
    NSDate *                       _updated; // 0x18
    BOOL                           _loading; // 0x20
    NSString *                     _lastCity; // 0x28
    BOOL                           _hasData; // 0x30
    BOOL                           _isDay; // 0x31
    NSString *                     _problem; // 0x38
    NSString *                     _place; // 0x40
    double                         _temperature; // 0x48
    double                         _feelsLike; // 0x50
    double                         _high; // 0x58
    double                         _low; // 0x60
    long long                      _rainChance; // 0x68
    long long                      _code; // 0x70
    NSArray *                      _hours; // 0x78
    NSArray *                      _sunrises; // 0x80
    NSArray *                      _sunsets; // 0x88
    NSDate *                       _attempted; // failed-request backoff, not forecast freshness
}

@property (nonatomic, assign, readonly) BOOL hasData;
@property (nonatomic, strong, readonly) NSString * problem;
@property (nonatomic, strong, readonly) NSString * place;
@property (nonatomic, assign, readonly) double temperature;
@property (nonatomic, assign, readonly) double feelsLike;
@property (nonatomic, assign, readonly) double high;
@property (nonatomic, assign, readonly) double low;
@property (nonatomic, assign, readonly) long long rainChance;
@property (nonatomic, assign, readonly) long long code;
@property (nonatomic, assign, readonly) BOOL isDay;
@property (nonatomic, strong, readonly) NSArray * hours;
@property (nonatomic, strong, readonly) NSArray * sunrises;
@property (nonatomic, strong, readonly) NSArray * sunsets;

#pragma mark - class methods
+ (GLTWeather *)sharedWeather;
+ (NSString *)symbolForCode:(NSInteger)arg1 isDay:(BOOL)arg2;
+ (NSString *)descriptionForCode:(NSInteger)arg1;
+ (NSString *)temperatureString:(double)arg1;

#pragma mark - instance methods
- (instancetype)init;
- (void)refreshForcing:(BOOL)arg1;
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)arg1;
- (void)locationManager:(CLLocationManager *)arg1 didUpdateLocations:(NSArray *)arg2;
- (void)locationManager:(CLLocationManager *)arg1 didFailWithError:(NSError *)arg2;
- (void)failWithProblem:(id)arg1;
- (void)fetchForLocation:(CLLocation *)arg1 place:(NSString *)arg2;
- (void)applyForecast:(NSDictionary *)arg1 place:(NSString *)arg2;


@end
