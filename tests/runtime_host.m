// Executes the actual admission helper with Foundation/ObjC receiver doubles.
// This does not exercise UIKit or SpringBoard.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "GLTRuntime.h"

#import <stdio.h>
#import <stdlib.h>

@interface GLTABIProbe : NSObject
- (void)acceptObject:(id)object;
- (NSString *)objectValue;
- (BOOL)flagValue;
- (CGSize)sizeThatFits:(CGSize)size;
@end
@implementation GLTABIProbe
- (void)acceptObject:(id)object { (void)object; }
- (NSString *)objectValue { return @"value"; }
- (BOOL)flagValue { return YES; }
- (CGSize)sizeThatFits:(CGSize)size { return size; }
@end


static void Require(BOOL condition, const char *message) {
    if (!condition) {
        fprintf(stderr, "GLINT_RUNTIME_HOST_FAIL: %s\n", message);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        Class cls = [GLTABIProbe class];
        Require(GLTMethodMatches(cls, @selector(acceptObject:), @encode(void), @[@"@"]), "object input");
        Require(GLTMethodMatches(cls, @selector(objectValue), @encode(id), @[]), "typed object return");
        Require(GLTMethodMatches(cls, @selector(flagValue), @encode(BOOL), @[]), "boolean return");
        Require(GLTMethodMatches(cls, @selector(sizeThatFits:), @encode(CGSize),
                                 @[[NSString stringWithUTF8String:@encode(CGSize)]]), "struct ABI");
        Require(!GLTMethodMatches(Nil, @selector(flagValue), @encode(BOOL), @[]), "missing class rejected");
        Require(!GLTMethodMatches(cls, NSSelectorFromString(@"notImplemented"), @encode(void), @[]), "missing selector rejected");
        Require(!GLTMethodMatches(cls, @selector(flagValue), @encode(id), @[]), "wrong return rejected");
        Require(!GLTMethodMatches(cls, @selector(acceptObject:), @encode(void), @[]), "wrong arity rejected");
        Require(!GLTMethodMatches(cls, @selector(acceptObject:), @encode(void), @[@"d"]), "wrong input rejected");
        GLTSetStatusBarHooksReady(NO);
        Require(!GLTStatusBarHooksReady(), "initial closed admission");
        GLTSetStatusBarHooksReady(YES);
        Require(GLTStatusBarHooksReady(), "successful admission recorded");
        GLTSetStatusBarHooksReady(NO);
        Require(!GLTStatusBarHooksReady(), "admission can be withdrawn");

        puts("GLINT_RUNTIME_HOST_PASS");
    }
    return 0;
}
