// Runtime admission shared by hooks and overlay consumers. No authorization writes.
#import "GLTRuntime.h"
#import <objc/runtime.h>
#import <notify.h>
#import <string.h>

NSString *const GLTLockStateDidChangeNotification = @"GLTLockStateDidChangeNotification";
static BOOL gltStatusBarReady;

static const char *GLTUnqualifiedType(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL GLTEqualType(const char *actual, const char *expected) {
    actual = GLTUnqualifiedType(actual);
    expected = GLTUnqualifiedType(expected);
    if (!actual || !expected) return NO;
    if (actual[0] == '@' && expected[0] == '@') {
        return (actual[1] == '?') == (expected[1] == '?');
    }
    return strcmp(actual, expected) == 0;
}

BOOL GLTMethodMatches(Class cls, SEL selector, const char *returnType,
                      NSArray<NSString *> *argumentTypes) {
    if (!cls || !selector || !returnType) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return NO;
    const char *encoding = method_getTypeEncoding(method);
    if (!encoding) return NO;
    @try {
        NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:encoding];
        if (!signature || signature.numberOfArguments != argumentTypes.count + 2) return NO;
        if (!GLTEqualType(signature.methodReturnType, returnType)) return NO;
        for (NSUInteger i = 0; i < argumentTypes.count; i++) {
            if (!GLTEqualType([signature getArgumentTypeAtIndex:i + 2], argumentTypes[i].UTF8String)) {
                return NO;
            }
        }
        return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

BOOL GLTDeviceIsLocked(void) {
    static int token = -1;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (notify_register_check("com.apple.springboard.lockstate", &token) != NOTIFY_STATUS_OK) {
            token = -1;
        }
    });
    uint64_t state = 1;
    if (token < 0 || notify_get_state(token, &state) != NOTIFY_STATUS_OK) return YES;
    return state != 0;
}

BOOL GLTStatusBarHooksReady(void) {
    return gltStatusBarReady;
}

void GLTSetStatusBarHooksReady(BOOL ready) {
    gltStatusBarReady = ready;
}
