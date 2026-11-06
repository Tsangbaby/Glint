//
//  GLTWeatherHour.h
//  Glint (reconstructed interface)
//
//  Recovered from ObjC metadata of Glint.dylib 1.6.3
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>


@interface GLTWeatherHour : NSObject
{
    BOOL                           _isDay; // 0x08
    NSDate *                       _date; // 0x10
    double                         _temperature; // 0x18
    long long                      _code; // 0x20
}

@property (nonatomic, strong) NSDate * date;
@property (nonatomic, assign) double temperature;
@property (nonatomic, assign) long long code;
@property (nonatomic, assign) BOOL isDay;

#pragma mark - class methods
#pragma mark - instance methods

@end
