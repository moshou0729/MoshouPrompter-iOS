//
//  SBSWindowHosting.h
//  MoshouPrompter
//
//  系统级悬浮窗：把任意 UIWindow 通过 SpringBoardServices 的
//  SBSAccessibilityWindowHostingController 注册成「无障碍窗口」，
//  该窗口由 SpringBoard 合成，因此即使本 App 切到后台也能继续显示在
//  其他 App（系统相机、抖音、腾讯会议等）之上。
//
//  全部通过 NSInvocation + NSSelectorFromString 动态调用，
//  不链接私有框架，编译期零依赖；运行时拿不到就返回 NO 自动降级。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SBSWindowHosting : NSObject

/// 当前系统是否提供 SBSAccessibilityWindowHostingController
+ (BOOL)isAvailable;

/// 把 window 注册为系统级悬浮窗。成功返回 YES。
+ (BOOL)registerWindow:(UIWindow *)window NS_SWIFT_NAME(register(_:));

/// 取消注册（必须先注册过同一个 window）
+ (void)unregisterWindow:(UIWindow *)window NS_SWIFT_NAME(unregister(_:));

@end

NS_ASSUME_NONNULL_END
