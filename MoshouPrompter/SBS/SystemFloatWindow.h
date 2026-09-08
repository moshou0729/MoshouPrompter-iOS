//
//  SystemFloatWindow.h
//  MoshouPrompter
//
//  系统级悬浮窗专用 UIWindow 子类。
//  对照 TrollSpeed (Lessica/TrollSpeed) 的 HUDMainWindow 实现，
//  覆写 UIKit 私有方法让该窗口脱离 App 前后台生命周期，
//  是「切到桌面/其它 App 后悬浮窗不消失」的关键。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SystemFloatWindow : UIWindow
@end

NS_ASSUME_NONNULL_END
