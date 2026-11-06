//
//  GLTUnlocks.h
//  Glint (reconstructed interface)
//
//  Recovered from ObjC metadata of Glint.dylib 1.6.3
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>


@interface GLTUnlocks : NSObject
{
    long long                      _today; // 0x08
    long long                      _yesterday; // 0x10
    int                            _lockToken; // 0x18
    BOOL                           _locked; // 0x1c
    NSString *                     _day; // 0x20
}

@property (nonatomic, assign, readonly) long long today;
@property (nonatomic, assign, readonly) long long yesterday;

#pragma mark - class methods
+ (GLTUnlocks *)sharedUnlocks;

#pragma mark - instance methods
- (instancetype)init;
- (void)rollOverIfNeeded;
- (void)lockStateChanged:(int)arg1;
- (void)save;

@end
