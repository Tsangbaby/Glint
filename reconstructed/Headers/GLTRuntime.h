#ifndef GLT_RUNTIME_H
#define GLT_RUNTIME_H

#import <Foundation/Foundation.h>

#ifndef GLINT_VERIFICATION_BUILD
#define GLINT_VERIFICATION_BUILD 0
#endif

#ifdef __cplusplus
extern "C" {
#endif

BOOL GLTMethodMatches(Class cls, SEL selector, const char *returnType,
                      NSArray<NSString *> *argumentTypes);
BOOL GLTDeviceIsLocked(void);
BOOL GLTStatusBarHooksReady(void);
void GLTSetStatusBarHooksReady(BOOL ready);
FOUNDATION_EXPORT NSString *const GLTLockStateDidChangeNotification;

#ifdef __cplusplus
}
#endif
#endif
