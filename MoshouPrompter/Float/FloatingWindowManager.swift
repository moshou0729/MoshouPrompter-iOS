import UIKit

extension Notification.Name {
    static let floatingPrompterStateChanged = Notification.Name("com.moshou.prompter.floatingStateChanged")
    static let prompterSettingsChanged = Notification.Name("com.moshou.prompter.settingsChanged")
}

/// 悬浮提词窗管理。
/// - 应用内悬浮：新建一个高 windowLevel 的 UIWindow，浮在本 App 所有界面之上。
/// - 系统级悬浮：额外把该 window 注册给 SpringBoardServices 的
///   SBSAccessibilityWindowHostingController，由 SpringBoard 合成，
///   即使切到系统相机 / 抖音 / 会议 App 也依然显示在最上层。
final class FloatingWindowManager {

    static let shared = FloatingWindowManager()

    private var window: UIWindow?
    private var hostingRegistered = false
    private var orientationObserver: NSObjectProtocol?
    private var registerAttempt = 0
    private var diagnostics = "未开启过悬浮窗"

    private init() {}

    var isShowing: Bool { return window != nil }

    var isSystemWideActive: Bool { return hostingRegistered }

    /// 最近一次系统级悬浮窗注册的诊断信息，直接展示给用户便于排查
    var lastDiagnostics: String { return diagnostics }

    /// 悬浮窗里滚动引擎的实时状态，直接展示给用户便于排查
    var engineStatus: String {
        guard let controller = window?.rootViewController as? FloatingPrompterViewController else {
            return "未开启悬浮窗"
        }
        return controller.statusLine()
    }

    var currentScriptID: String? {
        return (window?.rootViewController as? FloatingPrompterViewController)?.script.id
    }

    // MARK: - Show / Hide

    func show(script: Script) {
        if let existing = window?.rootViewController as? FloatingPrompterViewController {
            // 已经在显示：换成新的文稿
            existing.replace(script: script)
            if PrompterSettings.shared.systemWide, !hostingRegistered, let win = window {
                registerSystemWide(win)
            }
            return
        }

        let frame = FloatingWindowManager.initialFrame()
        // iOS 13 之后 UIWindow 必须挂到 UIWindowScene 上才会产生 CAContext，
        // 拿不到 contextId 就没法注册给 SpringBoard。
        let win: UIWindow
        if let scene = FloatingWindowManager.activeWindowScene() {
            win = UIWindow(windowScene: scene)
            win.frame = frame
        } else {
            win = UIWindow(frame: frame)
        }
        win.backgroundColor = UIColor.clear
        win.windowLevel = UIWindow.Level(rawValue: 10000010)
        win.isOpaque = false

        let controller = FloatingPrompterViewController(script: script)
        win.rootViewController = controller
        win.isHidden = false
        // 必须 makeKeyAndVisible：只设 isHidden=false 时部分系统不会立即建 context
        win.makeKeyAndVisible()
        window = win

        registerAttempt = 0
        if PrompterSettings.shared.systemWide {
            registerSystemWide(win)
        } else {
            diagnostics = "系统级悬浮已在「设置」中关闭"
        }

        installOrientationObserver()
        NotificationCenter.default.post(name: .floatingPrompterStateChanged, object: nil)
    }

    /// 设置页开关「系统级悬浮窗」时对已显示的悬浮窗立即生效
    func applySystemWideSetting() {
        guard let win = window else { return }
        if PrompterSettings.shared.systemWide {
            if !hostingRegistered {
                registerAttempt = 0
                registerSystemWide(win)
            }
        } else if hostingRegistered {
            SBSWindowHosting.unregister(win)
            hostingRegistered = false
            KeepAlive.shared.stop()
            diagnostics = "已按设置关闭系统级悬浮：" + SBSWindowHosting.diagnostics()
        }
    }

    /// App 回到前台后调用：scene 重新激活时，之前注册给 SpringBoard 的 context
    /// 可能已经失效（表现就是「多用几次、一返回桌面悬浮窗就没了」），这里重新断言一次。
    func reassertHosting() {
        guard let win = window, PrompterSettings.shared.systemWide else { return }
        // 回到前台时，把 window 重新置为 key 并刷新其 CAContext，
        // 防止 contextId 失效导致「多次开关后悬浮窗不再显示」。
        win.isHidden = false
        win.makeKeyAndVisible()
        if hostingRegistered {
            SBSWindowHosting.unregister(win)
            hostingRegistered = false
        }
        registerAttempt = 0
        registerSystemWide(win)
    }

    /// App 切到后台后调用：iOS 14 上 SpringBoard 会在 1 秒左右释放 SBS contextId，
    /// 导致悬浮窗消失。这里主动 unregister + 强制刷新 window 的 CAContext + 重新注册，
    /// 让 SpringBoard 继续合成同一 window。
    func reassertForBackground() {
        guard let win = window, PrompterSettings.shared.systemWide else { return }
        if hostingRegistered {
            SBSWindowHosting.unregister(win)
            hostingRegistered = false
        }
        // 强制 window 重新进入显示流程，触发 CAContext 重新生成
        win.isHidden = true
        DispatchQueue.main.async {
            win.isHidden = false
            win.makeKeyAndVisible()
            self.registerAttempt = 0
            self.registerSystemWide(win)
        }
    }

    /// KeepAlive 的 CADisplayLink 每秒调一次：轻量级「触摸」让 SpringBoard
    /// 知道 SBS 窗口仍然有效。避免在 background 下 1 秒后被回收。
    func touchForBackground() {
        guard let win = window, hostingRegistered, PrompterSettings.shared.systemWide else { return }
        // 把 contextId 重新注册一次（contextId 一样，SpringBoard 端会刷新合成状态）
        SBSWindowHosting.unregister(win)
        SBSWindowHosting.register(win)
    }

    /// 注册给 SpringBoard。contextId 可能要等下一个 runloop 才生成，所以带重试。
    private func registerSystemWide(_ win: UIWindow) {
        let ok = SBSWindowHosting.register(win)
        diagnostics = SBSWindowHosting.diagnostics()
        if ok {
            hostingRegistered = true
            KeepAlive.shared.start()
            return
        }
        guard registerAttempt < 4 else {
            diagnostics = "注册失败（已重试 4 次）：" + SBSWindowHosting.diagnostics()
            return
        }
        registerAttempt += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, self.window === win else { return }
            self.registerSystemWide(win)
        }
    }

    static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
    }

    func hide() {
        if let win = window, hostingRegistered {
            SBSWindowHosting.unregister(win)
            diagnostics = "已关闭：" + SBSWindowHosting.diagnostics()
        }
        hostingRegistered = false
        registerAttempt = 0
        KeepAlive.shared.stop()

        window?.isHidden = true
        window?.rootViewController = nil
        window = nil

        if let observer = orientationObserver {
            NotificationCenter.default.removeObserver(observer)
            orientationObserver = nil
        }
        NotificationCenter.default.post(name: .floatingPrompterStateChanged, object: nil)
    }

    // MARK: - Frame

    static func screenBounds() -> CGRect {
        return UIScreen.main.bounds
    }

    static func initialFrame() -> CGRect {
        let bounds = screenBounds()
        // 默认尺寸：宽 = 屏宽 - 32（左右各 16pt 边距），高 = 屏高 * 0.24。
        // 顶部 32pt 是 dragBar，剩下 24% - 32pt 给文字 + 控制条。
        let defaultFrame = CGRect(x: 16,
                                  y: 80,
                                  width: bounds.width - 32,
                                  height: max(160, bounds.height * 0.24))
        guard let saved = PrompterSettings.shared.floatFrame else { return defaultFrame }
        return clamp(saved, in: bounds)
    }

    static func clamp(_ frame: CGRect, in bounds: CGRect) -> CGRect {
        let minSize: CGFloat = 140
        var width = min(max(frame.width, minSize), bounds.width - 8)
        var height = min(max(frame.height, 120), bounds.height - 40)
        var x = min(max(frame.origin.x, 4), max(4, bounds.width - width - 4))
        var y = min(max(frame.origin.y, 30), max(30, bounds.height - height - 4))
        if x + width > bounds.width - 4 {
            width = max(minSize, bounds.width - x - 4)
        }
        if y + height > bounds.height - 4 {
            height = max(120, bounds.height - y - 4)
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func installOrientationObserver() {
        guard orientationObserver == nil else { return }
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main) { [weak self] _ in
                guard let self = self, let win = self.window else { return }
                win.frame = FloatingWindowManager.clamp(win.frame, in: FloatingWindowManager.screenBounds())
                PrompterSettings.shared.floatFrame = win.frame
            }
    }
}
