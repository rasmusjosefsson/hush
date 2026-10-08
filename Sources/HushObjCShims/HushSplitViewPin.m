#import "HushSplitViewPin.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

static void HushSwallowIMP(Class cls, SEL sel, IMP empty) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    const char *types = method_getTypeEncoding(m);
    if (!class_addMethod(cls, sel, empty, types)) {
        method_setImplementation(m, empty);
    }
}

void HushPinSplitViewDivider(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // On modern macOS the divider is driven by gesture recognizers, not
        // mouseDown. Block them at every level so the sidebar can never be
        // dragged to resize or double-clicked to collapse.
        Class cls = [NSSplitView class];

        // 1. Never install the drag/double-click recognizers.
        HushSwallowIMP(cls, NSSelectorFromString(@"_initGestureRecognizers"),
                       imp_implementationWithBlock(^(id self) {}));

        // 2. If they're ever installed anyway, their actions do nothing.
        IMP swallowSender = imp_implementationWithBlock(^(id self, id sender) {});
        HushSwallowIMP(cls, NSSelectorFromString(@"_didTriggerDragGestureRecognizer:"), swallowSender);
        HushSwallowIMP(cls, NSSelectorFromString(@"_didTriggerDoubleClickGestureRecognizer:"), swallowSender);

        // 3. Block only the divider's resize cursor — pass every other
        // cursor rect (I-beam, pointer) through untouched.
        SEL addCursorSel = @selector(addCursorRect:cursor:);
        Method addCursorM = class_getInstanceMethod(cls, addCursorSel);
        if (addCursorM) {
            IMP orig = method_getImplementation(addCursorM);
            IMP filtered = imp_implementationWithBlock(^(id self, CGRect rect, NSCursor *cursor) {
                if (cursor == [NSCursor resizeLeftRightCursor] ||
                    cursor == [NSCursor resizeUpDownCursor] ||
                    cursor == [NSCursor openHandCursor] ||
                    cursor == [NSCursor closedHandCursor]) {
                    return;
                }
                ((void (*)(id, SEL, CGRect, id))orig)(self, addCursorSel, rect, cursor);
            });
            method_setImplementation(addCursorM, filtered);
        }

        // 4. Belt and braces for the classic mouseDown-driven divider path.
        HushSwallowIMP(cls, @selector(mouseDown:), swallowSender);
        HushSwallowIMP(cls, @selector(rightMouseDown:), swallowSender);
        const char *names[] = {"NSSplitDividerView", "NSSplitViewDividerView", "NSVibrantSplitDividerView"};
        for (int i = 0; i < 3; i++) {
            Class d = NSClassFromString([NSString stringWithUTF8String:names[i]]);
            if (!d) continue;
            HushSwallowIMP(d, @selector(mouseDown:), swallowSender);
            HushSwallowIMP(d, @selector(rightMouseDown:), swallowSender);
        }
    });
}
