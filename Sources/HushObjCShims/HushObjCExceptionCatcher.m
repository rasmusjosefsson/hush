#import "HushObjCExceptionCatcher.h"

NSErrorDomain const HushObjCExceptionErrorDomain = @"com.hush.objc-exception";

NSString *const HushObjCExceptionNameKey = @"HushObjCExceptionName";
NSString *const HushObjCExceptionReasonKey = @"HushObjCExceptionReason";
NSString *const HushObjCExceptionUserInfoKey = @"HushObjCExceptionUserInfo";
NSString *const HushObjCExceptionCallStackKey = @"HushObjCExceptionCallStack";

BOOL HushTryBlock(NS_NOESCAPE void (^block)(void),
                  NSError * _Nullable * _Nullable error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error != NULL) {
            NSMutableDictionary<NSErrorUserInfoKey, id> *userInfo = [NSMutableDictionary dictionary];

            NSString *name = exception.name ?: @"NSException";
            NSString *reason = exception.reason ?: @"(no reason)";
            userInfo[NSLocalizedDescriptionKey] =
                [NSString stringWithFormat:@"%@: %@", name, reason];
            userInfo[HushObjCExceptionNameKey] = name;
            userInfo[HushObjCExceptionReasonKey] = reason;
            if (exception.userInfo != nil) {
                userInfo[HushObjCExceptionUserInfoKey] = exception.userInfo;
            }
            NSArray<NSString *> *callStack = exception.callStackSymbols;
            if (callStack != nil) {
                userInfo[HushObjCExceptionCallStackKey] = callStack;
            }

            *error = [NSError errorWithDomain:HushObjCExceptionErrorDomain
                                         code:0
                                     userInfo:userInfo];
        }
        return NO;
    }
}
