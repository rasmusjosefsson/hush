import Foundation
import HushObjCShims

/// Runs `block` inside an Objective-C `@try`/`@catch` trampoline.
/// Swift cannot catch NSException — this converts them to NSError.
@discardableResult
func catchingObjCException<T>(_ block: () throws -> T) throws -> T {
    var result: Result<T, Error>?
    var objcError: NSError?
    let ok = HushTryBlock({
        do {
            result = .success(try block())
        } catch {
            result = .failure(error)
        }
    }, &objcError)

    if !ok {
        throw objcError ?? NSError(
            domain: HushObjCExceptionErrorDomain,
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Unknown Objective-C exception"]
        )
    }

    switch result {
    case .success(let value):
        return value
    case .failure(let error):
        throw error
    case .none:
        throw NSError(
            domain: HushObjCExceptionErrorDomain,
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "catchingObjCException produced no result"]
        )
    }
}
