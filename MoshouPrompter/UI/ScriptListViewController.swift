import UIKit

final class ScriptListViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let cellIdentifier = "ScriptCell"
    private var floatingObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "墨守提词器"
        view.backgroundColor = Theme.background
        setupTableView()
        setupNavigationItems()
        setupFloatingObserver()
    }

    deinit {
        if let observer = floatingObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
        updateEmptyState()
        refreshFloatingItem()
    }

    // MARK: - Setup

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = Theme.background
        tableView.separatorColor = Theme.separator
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellIdentifier)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let footer = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 60))
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textColor = Theme.subtext
        label.font = UIFont.systemFont(ofSize: 12)
        label.textAlignment = .center
        label.text = SBSWindowHosting.isAvailable()
            ? "左滑文稿 = 悬浮提词 · 点开文稿可全屏提词"
            : "当前系统不支持系统级悬浮，悬浮窗仅在本 App 内显示"
        footer.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: footer.topAnchor, constant: 8)
        ])
        tableView.tableFooterView = footer
    }

    private func setupNavigationItems() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "新建",
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(createScript))
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "设置",
                                                           style: .plain,
                                                           target: self,
                                                           action: #selector(openSettings))
    }

    private func setupFloatingObserver() {
        floatingObserver = NotificationCenter.default.addObserver(
            forName: .floatingPrompterStateChanged,
            object: nil,
            queue: .main) { [weak self] _ in
                self?.refreshFloatingItem()
            }
    }

    private func refreshFloatingItem() {
        let create = UIBarButtonItem(title: "新建",
                                     style: .plain,
                                     target: self,
                                     action: #selector(createScript))
        create.tintColor = Theme.accent
        if FloatingWindowManager.shared.isShowing {
            let stop = UIBarButtonItem(title: "停止悬浮",
                                       style: .plain,
                                       target: self,
                                       action: #selector(stopFloating))
            stop.tintColor = Theme.danger
            navigationItem.rightBarButtonItems = [create, stop]
        } else {
            navigationItem.rightBarButtonItems = [create]
        }
    }

    // MARK: - Actions

    @objc private func createScript() {
        let script = ScriptStore.shared.add(title: "", text: "")
        open(script: script, isNew: true)
    }

    @objc private func openSettings() {
        let controller = SettingsViewController()
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func stopFloating() {
        FloatingWindowManager.shared.hide()
    }

    private func open(script: Script, isNew: Bool) {
        let controller = ScriptEditorViewController(script: script)
        controller.isNewScript = isNew
        navigationController?.pushViewController(controller, animated: true)
    }

    private func startFloating(script: Script) {
        FloatingWindowManager.shared.show(script: script)
        let systemWide = PrompterSettings.shared.systemWide
        let message: String
        if systemWide && FloatingWindowManager.shared.isSystemWideActive {
            message = "悬浮窗已开启，切到相机/抖音也会浮在最上层"
        } else if systemWide {
            message = "系统级悬浮注册失败，已降级为应用内悬浮窗"
        } else {
            message = "悬浮窗已开启（仅本 App 内显示）"
        }
        let alert = UIAlertController(
            title: "墨守提词器",
            message: message + "\n\n诊断信息：\n" + FloatingWindowManager.shared.lastDiagnostics,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    private func updateEmptyState() {
        if ScriptStore.shared.scripts.isEmpty {
            let container = UIView(frame: tableView.bounds)
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 0
            label.textAlignment = .center
            label.textColor = Theme.subtext
            label.font = UIFont.systemFont(ofSize: 15)
            label.text = "还没有文稿\n点右上角「新建」开始写第一篇"
            container.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
            tableView.backgroundView = container
        } else {
            tableView.backgroundView = nil
        }
    }
}

// MARK: - UITableViewDataSource

extension ScriptListViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return ScriptStore.shared.scripts.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath)
        let script = ScriptStore.shared.scripts[indexPath.row]
        cell.backgroundColor = Theme.panel
        cell.textLabel?.text = script.displayTitle
        cell.textLabel?.textColor = Theme.text
        cell.detailTextLabel?.text = "\(script.wordCount) 字 · \(script.previewText)"
        cell.detailTextLabel?.textColor = Theme.subtext
        cell.accessoryType = .disclosureIndicator
        cell.selectedBackgroundView = UIView()
        cell.selectedBackgroundView?.backgroundColor = Theme.panel2
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ScriptListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let script = ScriptStore.shared.scripts[indexPath.row]
        open(script: script, isNew: false)
    }

    func tableView(_ tableView: UITableView,
                   leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let script = ScriptStore.shared.scripts[indexPath.row]
        let action = UIContextualAction(style: .normal, title: "悬浮提词") { [weak self] _, _, completion in
            self?.startFloating(script: script)
            completion(true)
        }
        action.backgroundColor = Theme.accent
        return UISwipeActionsConfiguration(actions: [action])
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let script = ScriptStore.shared.scripts[indexPath.row]
        let action = UIContextualAction(style: .destructive, title: "删除") { _, _, completion in
            ScriptStore.shared.delete(id: script.id)
            tableView.deleteRows(at: [indexPath], with: .automatic)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }
}
