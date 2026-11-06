//
//  GLTRecipient.h
//  Glint (reconstructed interface)
//
//  Recovered from ObjC metadata of Glint.dylib 1.6.3
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>


@interface GLTRecipient : NSObject
{
    NSString *                     _name; // 0x08
    NSString *                     _address; // 0x10
    NSString *                     _detail; // 0x18
}

@property (nonatomic, copy) NSString * name;
@property (nonatomic, copy) NSString * address;
@property (nonatomic, copy) NSString * detail;

#pragma mark - class methods
#pragma mark - instance methods

@end
