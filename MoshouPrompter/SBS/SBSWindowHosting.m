//
//  SBSWindowHosting.m
//  MoshouPrompter
//

#import "SBSWindowHosting.h"
#import <objc/runtime.h>
#import <dlfcn.h>

// 必须强引用持有，内部持有 BSServiceConnection，被释放后注册即失效
static id gHostingController = nil;
static NSMutableSet<NSNumber *> *gRegisteredContextIDs = nil;
static BOOL gTriedLoad = NO;
static BOOL gLoadOK = NO;
static NSString *gDiagnostics = @"尚未尝试注册";

@implementation SBSWindowHosting

+ (BOOL)loadFramework
{
    if (gTriedLoad) {
        return gLoadOK;
    }
    gTriedLoad = YES;

    // iOS 14 上 SpringBoardServices 位于 /System/Library/PrivateFrameworks
    NSArray<NSString *> *candidates = @[
        @"/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
        @"/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices.tbd",
    ];

    for (NSString *path in candidates) {
        void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW);
        if (handle != NULL) {
            gLoadOK = YES;
            gDiagnostics = [NSString stringWithFormat:@"SpringBoardServices 已加载：%@", path.lastPathComponent];
            return YES;
        }
    }

    // dlopen 失败也别急，某些系统镜像里它已被主可执行文件间接链接进来
    if (NSClassFromString(@"SBSAccessibilityWindowHostingController") != nil) {
        gLoadOK = YES;
        gDiagnostics = @"SpringBoardServices 已由系统预加载";
        return YES;
    }

    gLoadOK = NO;
    gDiagnostics = [NSString stringWithFormat:@"SpringBoardServices 加载失败：%s", dlerror() ?: "未知原因"];
    return NO;
}

+ (BOOL)isAvailable
{
    [self loadFramework];
    return NSClassFromString(@"SBSAccessibilityWindowHostingController") != nil;
}

+ (unsigned int)contextIdForWindow:(UIWindow *)window
{
    if (window == nil) {
        return 0;
    }
    SEL sel = NSSelectorFromString(@"_contextId");
    if (![window respondsToSelector:sel]) {
        gDiagnostics = @"UIWindow 不响应 _contextId";
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
    if (![self loadFramework]) {
        return NO;
    }

    Class controllerClass = NSClassFromString(@"SBSAccessibilityWindowHostingController");
    if (controllerClass == nil) {
        gDiagnostics = @"缺少 SBSAccessibilityWindowHostingController 类";
        return NO;
    }

    unsigned int contextId = [self contextIdForWindow:window];
    if (contextId == 0) {
        gDiagnostics = @"window 尚未产生 contextId（未显示或未挂到 windowScene）";
        return NO;
    }

    if (gHostingController == nil) {
        gHostingController = [[controllerClass alloc] init];
    }
    if (gHostingController == nil) {
        gDiagnostics = @"无法创建 SBSAccessibilityWindowHostingController 实例";
        return NO;
    }

    SEL sel = NSSelectorFromString(@"registerWindowWithContextID:atLevel:");
    if (![gHostingController respondsToSelector:sel]) {
        gDiagnostics = @"不响应 registerWindowWithContextID:atLevel:";
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
    gDiagnostics = [NSString stringWithFormat:@"已注册 contextId=%u level=%.0f", contextId, level];
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
    gDiagnostics = [NSString stringWithFormat:@"已取消注册 contextId=%u", contextId];
}

+ (NSString *)diagnostics
{
    return gDiagnostics ?: @"";
}

@end
