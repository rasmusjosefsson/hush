#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Swallows mouse events on NSSplitView's private divider view so dividers
/// can never be dragged (resize) or double-clicked (collapse). SwiftUI does
/// not expose a way to lock a NavigationSplitView column, and NSSplitView
/// asserts when its delegate is replaced, so this is done via method swizzle.
/// Call once at launch; idempotent.
FOUNDATION_EXPORT void HushPinSplitViewDivider(void);

NS_ASSUME_NONNULL_END
