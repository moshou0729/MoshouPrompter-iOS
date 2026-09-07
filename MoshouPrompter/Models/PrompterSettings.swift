import UIKit

final class PrompterSettings {

    static let shared = PrompterSettings()

    private let defaults = UserDefaults.standard

    private init() {}

    func registerDefaults() {
        defaults.register(defaults: [
            Keys.fontSize: 34.0,
            Keys.lineSpacing: 10.0,
            Keys.speed: 55.0,
            Keys.margin: 24.0,
            Keys.mirrorX: false,
            Keys.textHex: "#FFFFFF",
            Keys.bgHex: "#000000",
            Keys.bgOpacity: 0.85,
            Keys.centerLine: true,
            Keys.keepAwake: true,
            Keys.systemWide: true,
            Keys.floatFrame: ""
        ])
    }

    private enum Keys {
        static let fontSize = "prompter.fontSize"
        static let lineSpacing = "prompter.lineSpacing"
        static let speed = "prompter.speed"
        static let margin = "prompter.margin"
        static let mirrorX = "prompter.mirrorX"
        static let textHex = "prompter.textHex"
        static let bgHex = "prompter.bgHex"
        static let bgOpacity = "prompter.bgOpacity"
        static let centerLine = "prompter.centerLine"
        static let keepAwake = "prompter.keepAwake"
        static let systemWide = "prompter.systemWide"
        static let floatFrame = "prompter.floatFrame"
    }

    // MARK: - Typography

    var fontSize: CGFloat {
        get { return CGFloat(defaults.double(forKey: Keys.fontSize)) }
        set { defaults.set(Double(newValue), forKey: Keys.fontSize) }
    }

    var lineSpacing: CGFloat {
        get { return CGFloat(defaults.double(forKey: Keys.lineSpacing)) }
        set { defaults.set(Double(newValue), forKey: Keys.lineSpacing) }
    }

    /// 滚动速度，单位：点/秒
    var speed: CGFloat {
        get { return CGFloat(defaults.double(forKey: Keys.speed)) }
        set { defaults.set(Double(newValue), forKey: Keys.speed) }
    }

    var margin: CGFloat {
        get { return CGFloat(defaults.double(forKey: Keys.margin)) }
        set { defaults.set(Double(newValue), forKey: Keys.margin) }
    }

    var mirrorX: Bool {
        get { return defaults.bool(forKey: Keys.mirrorX) }
        set { defaults.set(newValue, forKey: Keys.mirrorX) }
    }

    var textColor: UIColor {
        get { return UIColor(hex: defaults.string(forKey: Keys.textHex) ?? "#FFFFFF") }
        set { defaults.set(newValue.hexString(), forKey: Keys.textHex) }
    }

    var backgroundColor: UIColor {
        get { return UIColor(hex: defaults.string(forKey: Keys.bgHex) ?? "#000000") }
        set { defaults.set(newValue.hexString(), forKey: Keys.bgHex) }
    }

    var bgOpacity: CGFloat {
        get { return CGFloat(defaults.double(forKey: Keys.bgOpacity)) }
        set { defaults.set(Double(newValue), forKey: Keys.bgOpacity) }
    }

    var centerLine: Bool {
        get { return defaults.bool(forKey: Keys.centerLine) }
        set { defaults.set(newValue, forKey: Keys.centerLine) }
    }

    var keepAwake: Bool {
        get { return defaults.bool(forKey: Keys.keepAwake) }
        set { defaults.set(newValue, forKey: Keys.keepAwake) }
    }

    var systemWide: Bool {
        get { return defaults.bool(forKey: Keys.systemWide) }
        set { defaults.set(newValue, forKey: Keys.systemWide) }
    }

    var floatFrame: CGRect? {
        get {
            let raw = defaults.string(forKey: Keys.floatFrame) ?? ""
            if raw.isEmpty { return nil }
            let rect = CGRectFromString(raw)
            if rect.width < 80 || rect.height < 80 { return nil }
            return rect
        }
        set {
            if let rect = newValue {
                defaults.set(NSStringFromCGRect(rect), forKey: Keys.floatFrame)
            } else {
                defaults.set("", forKey: Keys.floatFrame)
            }
        }
    }
}
