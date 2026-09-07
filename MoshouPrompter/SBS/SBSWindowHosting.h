//
//  SBSWindowHosting.h
//  MoshouPrompter
//
//  系统级悬浮窗：把任意 UIWindow 通过 SpringBoardServices 的
//  SBSAccessibilityWindowHostingController 注册成「无障碍窗口」，
//  该窗口由 SpringBoard 合成，因此即使本 App 切到后台也能继续显示在
//  其他 App（系统相机、抖音、腾讯会议等）之上。
//
//  两个必要条件（缺一不可，参考 TrollSpeed 的实现）：
//   1. 必须先 dlopen SpringBoardServices 私有框架，否则 NSClassFromString 拿不到类；
//   2. 安装包必须带 com.apple.springboard.accessibility-window-hosting  entitlement，
//      否则 SpringBoard 侧会静默拒绝（调用不报错，但窗口不显示）。
//
//  全部通过 NSInvocation + NSSelectorFromString 动态调用，
//  不链接私有框架，编译期零依赖；运行时拿不到就返回 NO 自动降级。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SBSWindowHosting : NSObject

/// 当前系统是否提供 SBSAccessibilityWindowHostingController
+ (BOOL)isAvailable;

/// 强制 dlopen SpringBoardServices。返回是否成功。
+ (BOOL)loadFramework;

/// 取 window 的 CAContext id（私有 _contextId）。为 0 表示 window 还没有上下文。
+ (unsigned int)contextIdForWindow:(UIWindow *)window;

/// 把 window 注册为系统级悬浮窗。成功返回 YES。
+ (BOOL)registerWindow:(UIWindow *)window NS_SWIFT_NAME(register(_:));

/// 取消注册（必须先注册过同一个 window）
+ (void)unregisterWindow:(UIWindow *)window NS_SWIFT_NAME(unregister(_:));

/// 最近一次操作的诊断信息，便于定位「为什么悬浮窗没跨 App 显示」
+ (NSString *)diagnostics;

@end

NS_ASSUME_NONNULL_END
