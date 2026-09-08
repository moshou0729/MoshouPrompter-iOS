//
//  SystemFloatWindow.m
//  MoshouPrompter
//
//  覆写 UIKit 私有方法让 UIWindow 变成「系统级持久窗口」。
//  参照 TrollSpeed (Lessica/TrollSpeed) 的 HUDMainWindow.mm：
//
//    + (BOOL)_isSystemWindow { return YES; }
//    - (BOOL)_isWindowServerHostingManaged { return NO; }
//    - (BOOL)_ignoresHitTest { return [HUDRootViewController passthroughMode]; }
//    - (BOOL)_isSecure { return YES; }
//    - (BOOL)_shouldCreateContextAsSecure { return YES; }
//
//  为什么必须有这个类（踩坑记录）：
//  1. iOS 14 起普通 UIWindow 默认由 WindowServer「托管」(hosting managed)，
//     窗口的生命周期绑定 App 的场景 —— App 一退到后台，WindowServer 立刻
//     把窗口撤掉，表现就是「切到桌面悬浮窗 1 秒后消失」。
//     把 _isWindowServerHostingManaged 覆写为 NO 后，窗口改用自身 CAContext，
//     通过 SBSAccessibilityWindowHostingController 注册给 SpringBoard 的
//     contextId 不再随 App 后台被释放，SpringBoard 端持续合成显示。
//  2. _isSystemWindow = YES 告诉 UIKit 别把本窗口当普通 App 窗口处理
//     （普通窗口在场景退到后台时会被 UIKit 隐藏）。
//  3. Swift 无法覆写这些 SDK 未声明的 selector（编译器直接报错），
//     必须用 ObjC 类承载 —— ObjC 运行时按 selector 查找实现，
//     子类实现同名方法即完成覆写，无需父类预先声明。
//
//  与 TrollSpeed 的差异：TrollSpeed 用 _isSecure=YES（防截屏/录屏）。
//  提词器不需要防录屏（用户可能要录提词过程），所以这里保持 NO，
//  内容可被系统截屏/录屏正常捕获。
//

#import "SystemFloatWindow.h"

@implementation SystemFloatWindow

// 标记为「系统窗口」：App 场景退到后台时 UIKit 不会隐藏/撤掉它。
+ (BOOL)_isSystemWindow
{
    return YES;
}

// ★核心：脱离 WindowServer 托管，改用自有 CAContext。
// App 进后台后 contextId 继续有效，悬浮窗跨 App 持续显示。
- (BOOL)_isWindowServerHostingManaged
{
    return NO;
}

// 窗口本身不穿透（点击穿透由浮窗内容层的 PassthroughView 控制）。
- (BOOL)_ignoresHitTest
{
    return NO;
}

// 不要求 secure context：提词内容需要能被录屏/截屏正常看到。
- (BOOL)_isSecure
{
    return NO;
}

- (BOOL)_shouldCreateContextAsSecure
{
    return NO;
}

@end
