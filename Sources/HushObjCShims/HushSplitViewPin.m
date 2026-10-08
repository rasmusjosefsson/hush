#import "HushSplitViewPin.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

static void HushSwallowMouse(Class cls, SEL sel) {
    IMP empty = imp_implementationWithBlock(^(NSView *view, NSEvent *event) {
        // Swallow: divider mouse down/double-click starts a resize or collapse.
    });
    if (!class_addMethod(cls, sel, empty, "v@:@")) {
        Method existing = class_getInstanceMethod(cls, sel);
        method_setImplementation(existing, empty);
    }
}

void HushPinSplitViewDivider(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"NSSplitViewDividerView");
        if (!cls) return;
        HushSwallowMouse(cls, @selector(mouseDown:));
        HushSwallowMouse(cls, @selector(rightMouseDown:));
    });
}
