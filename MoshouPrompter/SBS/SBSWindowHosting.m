//
//  SBSWindowHosting.m
//  MoshouPrompter
//

#import "SBSWindowHosting.h"
#import <objc/runtime.h>

// 必须强引用持有，内部持有 BSServiceConnection，被释放后注册即失效
static id gHostingController = nil;
static NSMutableSet<NSNumber *> *gRegisteredContextIDs = nil;

@implementation SBSWindowHosting

+ (BOOL)isAvailable
{
    return NSClassFromString(@"SBSAccessibilityWindowHostingController") != nil;
}

+ (unsigned int)contextIdForWindow:(UIWindow *)window
{
    if (window == nil) {
        return 0;
    }
    SEL sel = NSSelectorFromString(@"_contextId");
    if (![window respondsToSelector:sel]) {
        return 0;
    }
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:"I@:"];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.selector = sel;
    [invocation setTarget:window];
    [invocation invoke];
    unsigned int contextId = 0;
    [invocation getReturnValue:&contextId];
    return contextId;
}

+ (BOOL)registerWindow:(UIWindow *)window
{
    Class controllerClass = NSClassFromString(@"SBSAccessibilityWindowHostingController");
    if (controllerClass == nil) {
        return NO;
    }
    unsigned int contextId = [self contextIdForWindow:window];
    if (contextId == 0) {
        return NO;
    }
    if (gHostingController == nil) {
        gHostingController = [[controllerClass alloc] init];
    }
    if (gHostingController == nil) {
        return NO;
    }
    SEL sel = NSSelectorFromString(@"registerWindowWithContextID:atLevel:");
    if (![gHostingController respondsToSelector:sel]) {
        return NO;
    }
    double level = (double)window.windowLevel;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:"v@:Id"];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.selector = sel;
    [invocation setTarget:gHostingController];
    [invocation setArgument:&contextId atIndex:2];
    [invocation setArgument:&level atIndex:3];
    [invocation invoke];

    if (gRegisteredContextIDs == nil) {
        gRegisteredContextIDs = [[NSMutableSet alloc] init];
    }
    [gRegisteredContextIDs addObject:@(contextId)];
    return YES;
}

+ (void)unregisterWindow:(UIWindow *)window
{
    if (gHostingController == nil) {
        return;
    }
    unsigned int contextId = [self contextIdForWindow:window];
    if (contextId == 0) {
        return;
    }
    SEL sel = NSSelectorFromString(@"unregisterWindowWithContextID:");
    if (![gHostingController respondsToSelector:sel]) {
        return;
    }
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:"v@:I"];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.selector = sel;
    [invocation setTarget:gHostingController];
    [invocation setArgument:&contextId atIndex:2];
    [invocation invoke];

    [gRegisteredContextIDs removeObject:@(contextId)];
}

@end
