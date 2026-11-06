// Executes the actual admission helper with Foundation/ObjC receiver doubles.
// This does not exercise UIKit or SpringBoard.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "GLTRuntime.h"
#import "GLTUnlocks.h"
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

// Persistence is replaced only in this host subclass; production transitions run unchanged.
@interface GLTUnlockProbe : GLTUnlocks
@property (nonatomic) NSInteger saves;
- (void)resetDay:(NSString *)day today:(long long)today yesterday:(long long)yesterday;
@end
@implementation GLTUnlockProbe
- (void)save { self.saves++; }
- (void)resetDay:(NSString *)day today:(long long)today yesterday:(long long)yesterday {
    _day = [day copy]; _today = today; _yesterday = yesterday;
    _locked = YES; _hasLockState = NO; self.saves = 0;
}
@end

static NSString *ProbeDay(NSDate *date) {
    NSDateComponents *parts = [[NSCalendar currentCalendar]
        components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:date];
    return [NSString stringWithFormat:@"%04ld-%02ld-%02ld", (long)parts.year, (long)parts.month, (long)parts.day];
}

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
        GLTUnlockProbe *counter = [GLTUnlockProbe new];
        NSDate *now = [NSDate date];
        NSCalendar *calendar = [NSCalendar currentCalendar];
        NSString *today = ProbeDay(now);
        [counter resetDay:today today:0 yesterday:7];
        [counter lockStateChanged:NO];
        Require(counter.today == 0 && counter.saves == 0, "first unlocked observation is only baseline");
        [counter lockStateChanged:YES]; [counter lockStateChanged:NO];
        Require(counter.today == 1 && counter.saves == 1, "one locked-to-unlocked transition");
        [counter lockStateChanged:NO];
        Require(counter.today == 1 && counter.saves == 1, "duplicate unlocked notification is ignored");
        [counter lockStateChanged:YES]; [counter lockStateChanged:NO];
        Require(counter.today == 2 && counter.yesterday == 7, "second transition retains yesterday");
        NSString *previous = ProbeDay([calendar dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:now options:0]);
        [counter resetDay:previous today:8 yesterday:3];
        Require(counter.today == 0 && counter.yesterday == 8 && counter.saves == 1, "one-day rollover in getters");
        NSString *older = ProbeDay([calendar dateByAddingUnit:NSCalendarUnitDay value:-2 toDate:now options:0]);
        [counter resetDay:older today:8 yesterday:3];
        Require(counter.yesterday == 0 && counter.today == 0 && counter.saves == 1, "explicit multi-day reset policy");
        puts("GLINT_UNLOCKS_HOST_PASS");
        puts("GLINT_RUNTIME_HOST_PASS");
    }
    return 0;
}
