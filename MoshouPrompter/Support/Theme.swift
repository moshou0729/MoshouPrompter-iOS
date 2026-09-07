import UIKit

enum Theme {
    static let background = UIColor(hex: "#12141A")
    static let panel = UIColor(hex: "#1C1F27")
    static let panel2 = UIColor(hex: "#262A34")
    static let separator = UIColor(hex: "#333844")
    static let text = UIColor(hex: "#F2F4F8")
    static let subtext = UIColor(hex: "#9AA3B2")
    static let accent = UIColor(hex: "#4DA3FF")
    static let danger = UIColor(hex: "#FF5C5C")

    static func applyGlobalAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Theme.panel
        appearance.titleTextAttributes = [NSAttributedString.Key.foregroundColor: Theme.text]
        appearance.largeTitleTextAttributes = [NSAttributedString.Key.foregroundColor: Theme.text]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = Theme.accent
        UINavigationBar.appearance().titleTextAttributes = [NSAttributedString.Key.foregroundColor: Theme.text]

        UITableView.appearance().backgroundColor = Theme.background
        UITableView.appearance().separatorColor = Theme.separator
        UITableViewCell.appearance().backgroundColor = Theme.panel
        UISwitch.appearance().onTintColor = Theme.accent
    }
}

extension UIColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt32 = 0
        Scanner(string: cleaned).scanHexInt32(&value)
        var r: UInt32 = 0
        var g: UInt32 = 0
        var b: UInt32 = 0
        var a: UInt32 = 255
        if cleaned.count >= 6 {
            r = (value >> 16) & 0xFF
            g = (value >> 8) & 0xFF
            b = value & 0xFF
            if cleaned.count >= 8 {
                a = (value >> 24) & 0xFF
            }
        }
        self.init(red: CGFloat(r) / 255.0,
                  green: CGFloat(g) / 255.0,
                  blue: CGFloat(b) / 255.0,
                  alpha: CGFloat(a) / 255.0)
    }

    func hexString() -> String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
