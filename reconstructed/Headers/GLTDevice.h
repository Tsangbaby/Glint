//
//  GLTDevice.h
//  Glint (reconstructed interface)
//
//  Recovered from ObjC metadata of Glint.dylib 1.6.3
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>


@interface GLTDevice : NSObject
{
    BOOL                           _charging; // 0x08
    BOOL                           _internal; // 0x09
    NSString *                     _identifier; // 0x10
    NSString *                     _name; // 0x18
    long long                      _percent; // 0x20
    UIImage *                      _glyph; // 0x28
    NSString *                     _details; // 0x30
}

@property (nonatomic, copy) NSString * identifier;
@property (nonatomic, copy) NSString * name;
@property (nonatomic, assign) long long percent;
@property (nonatomic, assign) BOOL charging;
@property (nonatomic, assign) BOOL internal;
@property (nonatomic, strong) UIImage * glyph;
@property (nonatomic, copy) NSString * details;

#pragma mark - class methods
#pragma mark - instance methods

@end
