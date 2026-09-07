import UIKit

final class ScriptEditorViewController: UIViewController {

    private var script: Script
    var isNewScript: Bool = false

    private let titleField = UITextField()
    private let textView = UITextView()
    private let countLabel = UILabel()
    private var keyboardHeight: CGFloat = 0

    init(script: Script) {
        self.script = script
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        setupUI()
        setupNavigationItems()
        setupKeyboardObservers()

        let tap = UITapGestureRecognizer(target: self, action: #selector(endEditingText))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        if isNewScript {
            titleField.becomeFirstResponder()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        persist()
    }

    // MARK: - UI

    private func setupUI() {
        let titleContainer = UIView()
        titleContainer.translatesAutoresizingMaskIntoConstraints = false
        titleContainer.backgroundColor = Theme.panel
        view.addSubview(titleContainer)

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.placeholder = "文稿标题"
        titleField.text = script.title
        titleField.textColor = Theme.text
        titleField.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        titleField.attributedPlaceholder = NSAttributedString(
            string: "文稿标题",
            attributes: [NSAttributedString.Key.foregroundColor: Theme.subtext])
        titleField.returnKeyType = .done
        titleField.delegate = self
        titleContainer.addSubview(titleField)

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.text = script.text
        textView.textColor = Theme.text
        textView.backgroundColor = Theme.background
        textView.font = UIFont.systemFont(ofSize: 17)
        textView.alwaysBounceVertical = true
        textView.delegate = self
        view.addSubview(textView)

        let toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.barTintColor = Theme.panel
        toolbar.tintColor = Theme.accent
        toolbar.isTranslucent = false
        view.addSubview(toolbar)

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.textColor = Theme.subtext
        countLabel.font = UIFont.systemFont(ofSize: 12)
        view.addSubview(countLabel)
        updateCount()

        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        toolbar.items = [
            UIBarButtonItem(title: "粘贴导入", style: .plain, target: self, action: #selector(importFromPasteboard)),
            spacer,
            UIBarButtonItem(title: "文件导入", style: .plain, target: self, action: #selector(importFromFile)),
            spacer,
            UIBarButtonItem(title: "全屏提词", style: .plain, target: self, action: #selector(startFullscreen)),
            spacer,
            UIBarButtonItem(title: "悬浮提词", style: .plain, target: self, action: #selector(startFloating))
        ]

        let bottom = view.safeAreaLayoutGuide.bottomAnchor
        NSLayoutConstraint.activate([
            titleContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            titleContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            titleContainer.heightAnchor.constraint(equalToConstant: 52),

            titleField.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor, constant: 16),
            titleField.trailingAnchor.constraint(equalTo: titleContainer.trailingAnchor, constant: -16),
            titleField.centerYAnchor.constraint(equalTo: titleContainer.centerYAnchor),

            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.topAnchor.constraint(equalTo: titleContainer.bottomAnchor),
            textView.bottomAnchor.constraint(equalTo: toolbar.topAnchor),

            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: bottom),
            toolbar.heightAnchor.constraint(equalToConstant: 44),

            countLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            countLabel.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -6)
        ])
    }

    private func setupNavigationItems() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完成",
                                                            style: .done,
                                                            target: self,
                                                            action: #selector(finishEditing))
    }

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillChange(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification,
                                               object: nil)
    }

    // MARK: - Persistence

    private func persist() {
        script.title = titleField.text ?? ""
        script.text = textView.text ?? ""
        script.updatedAt = Date()
        ScriptStore.shared.update(script)
    }

    private func updateCount() {
        countLabel.text = "\(textView.text.count) 字"
    }

    // MARK: - Actions

    @objc private func endEditingText() {
        view.endEditing(true)
    }

    @objc private func finishEditing() {
        view.endEditing(true)
        persist()
        navigationController?.popViewController(animated: true)
    }

    @objc private func importFromPasteboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            showAlert("剪贴板里没有文本")
            return
        }
        textView.text = text
        updateCount()
        persist()
    }

    @objc private func importFromFile() {
        let picker = UIDocumentPickerViewController(documentTypes: ["public.plain-text", "public.text"],
                                                    in: .import)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true, completion: nil)
    }

    @objc private func startFullscreen() {
        persist()
        let controller = PrompterViewController(script: script)
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true, completion: nil)
    }

    @objc private func startFloating() {
        persist()
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
        showAlert(message)
    }

    private func showAlert(_ message: String) {
        let alert = UIAlertController(title: "墨守提词器", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let height = max(0, view.bounds.height - frame.origin.y)
        keyboardHeight = height
        textView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: height, right: 0)
        textView.scrollIndicatorInsets = textView.contentInset
    }
}

// MARK: - UITextFieldDelegate

extension ScriptEditorViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

// MARK: - UITextViewDelegate

extension ScriptEditorViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updateCount()
    }
}

// MARK: - UIDocumentPickerDelegate

extension ScriptEditorViewController: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            showAlert("读取失败，请确认是 UTF-8 文本文件")
            return
        }
        textView.text = content
        if titleField.text?.isEmpty ?? true {
            titleField.text = url.deletingPathExtension().lastPathComponent
        }
        updateCount()
        persist()
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true, completion: nil)
    }
}
