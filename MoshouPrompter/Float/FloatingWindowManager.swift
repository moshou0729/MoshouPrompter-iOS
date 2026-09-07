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

    private init() {}

    var isShowing: Bool { return window != nil }

    var isSystemWideActive: Bool { return hostingRegistered }

    var currentScriptID: String? {
        return (window?.rootViewController as? FloatingPrompterViewController)?.script.id
    }

    // MARK: - Show / Hide

    func show(script: Script) {
        if let existing = window?.rootViewController as? FloatingPrompterViewController {
            // 已经在显示：换成新的文稿
            existing.replace(script: script)
            return
        }

        let win = UIWindow(frame: FloatingWindowManager.initialFrame())
        win.backgroundColor = UIColor.clear
        win.windowLevel = UIWindow.Level(rawValue: 10000010)
        win.isOpaque = false

        let controller = FloatingPrompterViewController(script: script)
        win.rootViewController = controller
        win.isHidden = false
        window = win

        let settings = PrompterSettings.shared
        if settings.systemWide {
            hostingRegistered = SBSWindowHosting.registerWindow(win)
            if hostingRegistered {
                KeepAlive.shared.start()
            }
        }

        installOrientationObserver()
        NotificationCenter.default.post(name: .floatingPrompterStateChanged, object: nil)
    }

    func hide() {
        if let win = window, hostingRegistered {
            SBSWindowHosting.unregisterWindow(win)
        }
        hostingRegistered = false
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
        let defaultFrame = CGRect(x: 8,
                                  y: 88,
                                  width: bounds.width - 16,
                                  height: max(180, bounds.height * 0.32))
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
