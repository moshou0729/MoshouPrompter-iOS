import UIKit

private enum SettingKind {
    case toggle(Bool, (Bool) -> Void)
    case slider(Float, Float, Float, (Float) -> Void)
    case segment([String], Int, (Int) -> Void)
    case info(String)
}

private struct SettingItem {
    let title: String
    let subtitle: String?
    let kind: SettingKind
}

final class SettingsViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var sections: [[SettingItem]] = []
    private var sectionTitles: [String] = []

    private var toggleHandlers: [Int: (Bool) -> Void] = [:]
    private var sliderHandlers: [Int: (Float) -> Void] = [:]
    private var segmentHandlers: [Int: (Int) -> Void] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        view.backgroundColor = Theme.background
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = Theme.background
        tableView.separatorColor = Theme.separator
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rebuild()
        tableView.reloadData()
    }

    // MARK: - Model

    private func rebuild() {
        let settings = PrompterSettings.shared
        sections = []
        sectionTitles = []

        sections.append([
            SettingItem(title: "字号", subtitle: nil,
                        kind: .slider(Float(settings.fontSize), 16, 96, { [weak self] value in
                            settings.fontSize = CGFloat(value)
                            self?.settingsDidChange()
                        })),
            SettingItem(title: "行距", subtitle: nil,
                        kind: .slider(Float(settings.lineSpacing), 0, 40, { [weak self] value in
                            settings.lineSpacing = CGFloat(value)
                            self?.settingsDidChange()
                        })),
            SettingItem(title: "左右边距", subtitle: nil,
                        kind: .slider(Float(settings.margin), 0, 80, { [weak self] value in
                            settings.margin = CGFloat(value)
                            self?.settingsDidChange()
                        })),
            SettingItem(title: "文字颜色", subtitle: nil,
                        kind: .segment(["白色", "淡黄", "淡绿", "青蓝"], colorIndex(settings.textColor), { [weak self] index in
                            settings.textColor = SettingsViewController.colorPresets[index]
                            self?.settingsDidChange()
                        }))
        ])
        sectionTitles.append("文字")

        sections.append([
            SettingItem(title: "滚动速度（点/秒）", subtitle: nil,
                        kind: .slider(Float(settings.speed), 5, 400, { [weak self] value in
                            settings.speed = CGFloat(value)
                            self?.settingsDidChange()
                        })),
            SettingItem(title: "水平镜像", subtitle: "配合提词器玻璃使用",
                        kind: .toggle(settings.mirrorX, { [weak self] value in
                            settings.mirrorX = value
                            self?.settingsDidChange()
                        })),
            SettingItem(title: "显示参考线", subtitle: nil,
                        kind: .toggle(settings.centerLine, { [weak self] value in
                            settings.centerLine = value
                            self?.settingsDidChange()
                        }))
        ])
        sectionTitles.append("滚动")

        let hostingAvailable = SBSWindowHosting.isAvailable()
        sections.append([
            SettingItem(title: "系统级悬浮窗",
                        subtitle: hostingAvailable
                            ? "开启后，切到相机 / 抖音 / 会议 App，提词窗仍然浮在最上层"
                            : "当前系统未提供该能力，只能在本 App 内悬浮",
                        kind: .toggle(settings.systemWide, { value in
                            settings.systemWide = value
                        })),
            SettingItem(title: "背景颜色", subtitle: nil,
                        kind: .segment(["纯黑", "深蓝", "深灰"], bgIndex(settings.backgroundColor), { [weak self] index in
                            settings.backgroundColor = SettingsViewController.bgPresets[index]
                            self?.settingsDidChange()
                        })),
            SettingItem(title: "悬浮窗不透明度", subtitle: nil,
                        kind: .slider(Float(settings.bgOpacity), 0.2, 1.0, { [weak self] value in
                            settings.bgOpacity = CGFloat(value)
                            self?.settingsDidChange()
                        })),
            SettingItem(title: "屏幕常亮", subtitle: "提词时防止自动锁屏",
                        kind: .toggle(settings.keepAwake, { [weak self] value in
                            settings.keepAwake = value
                            UIApplication.shared.isIdleTimerDisabled = value
                            self?.settingsDidChange()
                        }))
        ])
        sectionTitles.append("悬浮窗")

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        sections.append([
            SettingItem(title: "版本", subtitle: nil, kind: .info(version)),
            SettingItem(title: "系统级悬浮能力",
                        subtitle: nil,
                        kind: .info(hostingAvailable ? "可用" : "不可用")),
            SettingItem(title: "后台保活",
                        subtitle: nil,
                        kind: .info("静音音频"))
        ])
        sectionTitles.append("关于")
    }

    private static let colorPresets: [UIColor] = [
        UIColor(hex: "#FFFFFF"),
        UIColor(hex: "#FFE9A8"),
        UIColor(hex: "#B6F5C4"),
        UIColor(hex: "#A8E1FF")
    ]

    private static let bgPresets: [UIColor] = [
        UIColor(hex: "#000000"),
        UIColor(hex: "#04102A"),
        UIColor(hex: "#2A2A2A")
    ]

    private func colorIndex(_ color: UIColor) -> Int {
        let hex = color.hexString()
        for (index, preset) in SettingsViewController.colorPresets.enumerated() {
            if preset.hexString() == hex { return index }
        }
        return 0
    }

    private func bgIndex(_ color: UIColor) -> Int {
        let hex = color.hexString()
        for (index, preset) in SettingsViewController.bgPresets.enumerated() {
            if preset.hexString() == hex { return index }
        }
        return 0
    }

    private func settingsDidChange() {
        NotificationCenter.default.post(name: .prompterSettingsChanged, object: nil)
    }

    // MARK: - Control events

    @objc private func switchChanged(_ sender: UISwitch) {
        toggleHandlers[sender.tag]?(sender.isOn)
    }

    @objc private func sliderChanged(_ sender: UISlider) {
        sliderHandlers[sender.tag]?(sender.value)
        tableView.reloadData()
    }

    @objc private func segmentChanged(_ sender: UISegmentedControl) {
        segmentHandlers[sender.tag]?(sender.selectedSegmentIndex)
    }
}

// MARK: - UITableViewDataSource

extension SettingsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sectionTitles[section]
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = sections[indexPath.section][indexPath.row]
        let tag = indexPath.section * 100 + indexPath.row

        let cell: UITableViewCell
        switch item.kind {
        case .toggle:
            cell = dequeue("toggle")
            let toggle = UISwitch()
            toggle.onTintColor = Theme.accent
            toggle.tag = tag
            toggle.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            if case .toggle(let value, let handler) = item.kind {
                toggle.isOn = value
                toggleHandlers[tag] = handler
            }
            cell.detailTextLabel?.text = nil

        case .slider:
            cell = dequeue("slider")
            let slider = UISlider()
            slider.tintColor = Theme.accent
            slider.tag = tag
            slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
            slider.frame = CGRect(x: 0, y: 0, width: 160, height: 30)
            cell.accessoryView = slider
            cell.detailTextLabel?.text = nil
            if case .slider(let value, let min, let max, let handler) = item.kind {
                slider.minimumValue = min
                slider.maximumValue = max
                slider.value = value
                sliderHandlers[tag] = handler
                cell.detailTextLabel?.text = String(format: "%.0f", value)
            }

        case .segment:
            cell = dequeue("segment")
            if case .segment(let titles, let selected, let handler) = item.kind {
                let segment = UISegmentedControl(items: titles)
                segment.selectedSegmentIndex = selected
                segment.tag = tag
                segment.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)
                segment.frame = CGRect(x: 0, y: 0, width: 200, height: 30)
                cell.accessoryView = segment
                segmentHandlers[tag] = handler
            }
            cell.detailTextLabel?.text = nil

        case .info:
            cell = dequeue("info")
            if case .info(let value) = item.kind {
                cell.detailTextLabel?.text = value
            }
            cell.accessoryView = nil
        }

        cell.backgroundColor = Theme.panel
        cell.textLabel?.text = item.title
        cell.textLabel?.textColor = Theme.text
        cell.detailTextLabel?.textColor = Theme.subtext
        cell.selectionStyle = .none
        return cell
    }

    private func dequeue(_ identifier: String) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: identifier) {
            return cell
        }
        return UITableViewCell(style: .value1, reuseIdentifier: identifier)
    }
}

// MARK: - UITableViewDelegate

extension SettingsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 2 {
            return "系统级悬浮窗依赖 TrollStore / 越狱环境；普通 App Store 安装包无法跨 App 显示。开启后本 App 会循环播放一段静音音频用于后台保活，回到列表页点「停止悬浮」即可结束。"
        }
        return nil
    }
}
