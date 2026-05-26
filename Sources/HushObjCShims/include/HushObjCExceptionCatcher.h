#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const HushObjCExceptionErrorDomain;

FOUNDATION_EXPORT NSString *const HushObjCExceptionNameKey;
FOUNDATION_EXPORT NSString *const HushObjCExceptionReasonKey;
FOUNDATION_EXPORT NSString *const HushObjCExceptionUserInfoKey;
FOUNDATION_EXPORT NSString *const HushObjCExceptionCallStackKey;

/// Executes @c block inside an Objective-C @c \@try / @c \@catch trampoline.
/// Swift cannot catch NSException — this converts them to NSError.
FOUNDATION_EXPORT BOOL HushTryBlock(NS_NOESCAPE void (^block)(void),
                                    NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
