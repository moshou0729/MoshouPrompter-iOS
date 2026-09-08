import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        PrompterSettings.shared.registerDefaults()
        Theme.applyGlobalAppearance()
        UIApplication.shared.isIdleTimerDisabled = PrompterSettings.shared.keepAwake
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = Theme.background
        window.rootViewController = RootNavigationController(rootViewController: ScriptListViewController())
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // 悬浮窗口使用 SystemFloatWindow（_isWindowServerHostingManaged=NO），
        // context 不随后台失效，这里只兜底注册失败过的情况。
        FloatingWindowManager.shared.reassertHosting()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        ScriptStore.shared.save()
        // 注意：这里【不要】做任何 unregister / 重注册 / isHidden 切换。
        // 之前版本在进后台时 unregister+re-register，反而让 SpringBoard 在
        // unregister 的瞬间把窗口移除，表现为「切到桌面 1 秒后消失」。
        // 正确做法是注册一次后不动（TrollSpeed 模式），窗口存活靠
        // SystemFloatWindow 脱离 WindowServer 托管 + KeepAlive 音频保活。
    }

    func applicationWillTerminate(_ application: UIApplication) {
        ScriptStore.shared.save()
    }
}
