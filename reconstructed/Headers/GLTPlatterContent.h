//
//  GLTPlatterContent.h
//  Glint (reconstructed interface)
//
//  Recovered from ObjC metadata of Glint.dylib 1.6.3
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>


@interface GLTPlatterContent : UIView
{
    void (^                         _closeHandler)(void); // 0x08
    void (^                         _resizeHandler)(void); // 0x10
}

@property (nonatomic, copy) void (^closeHandler)(void);
@property (nonatomic, copy) void (^resizeHandler)(void);

#pragma mark - class methods
#pragma mark - instance methods
- (void)fillWith:(NSArray *)arg1;
- (void)close;
- (BOOL)wantsKeyboard;

@end
