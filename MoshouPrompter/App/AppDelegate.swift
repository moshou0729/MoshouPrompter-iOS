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
        // 回到前台时补一次系统级悬浮注册，防止 context 失效
        FloatingWindowManager.shared.reassertHosting()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        ScriptStore.shared.save()
        // iOS 14 上 SpringBoard 在 App 进 background 后 1 秒左右会释放 SBS 窗口的
        // contextId，导致悬浮窗消失。这里在 background 主动重新注册一次，
        // 配合 KeepAlive 的 CADisplayLink 心跳，强制 SpringBoard 继续合成。
        FloatingWindowManager.shared.reassertForBackground()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        ScriptStore.shared.save()
    }
}
