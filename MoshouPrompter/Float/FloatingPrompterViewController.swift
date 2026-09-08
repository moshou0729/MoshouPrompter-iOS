import UIKit

/// 根视图：开启「点击穿透」时，落在空白区域的触摸会返回 nil，
/// 从而穿透到下层 App（系统相机等），只有控制条仍然可点。
final class PassthroughView: UIView {

    var passthrough = false

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if passthrough, hit === self {
            return nil
        }
        return hit
    }
}

final class FloatingPrompterViewController: UIViewController {

    private(set) var script: Script
    private let engine = PrompterEngine()

    private var containerView: UIView!
    private var textArea: UIView!
    private var controlBar: UIStackView!
    private var resizeHandle: UIView!
    private var dragBar: UIView!
    private var dragBarGrip: UIView!
    private var progressWidthConstraint: NSLayoutConstraint!
    private var progressView: UIView!
    private var playButton: UIButton!
    private var passthroughButton: UIButton!

    private var isPassthrough = true
    private var panStartFrame: CGRect = .zero
    private var hideBarsTimer: Timer?
    private var settingsObserver: NSObjectProtocol?

    init(script: Script) {
        self.script = script
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Lifecycle

    override func loadView() {
        // 注意：这里是 window 的坐标系，origin 必须是 (0,0)。
        // 用屏幕坐标（initialFrame 的 x=8,y=88）会让整块内容往下偏，
        // 控制条被顶出 window 底部，按钮就永远点不到。
        let size = FloatingWindowManager.initialFrame().size
        let root = PassthroughView(frame: CGRect(origin: .zero, size: size))
        root.backgroundColor = UIColor.clear
        root.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        applySettings()
        engine.apply(text: script.text)
        engine.play()

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .prompterSettingsChanged,
            object: nil,
            queue: .main) { [weak self] _ in
                guard let self = self else { return }
                self.applySettings()
                self.engine.apply(text: self.script.text)
                self.view.setNeedsLayout()
            }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // play() 在 viewDidLoad 就调过，但那时 textView 还没布局、
        // scrollableDistance 还是 0，引擎会在第一次 tick 就停机。这里补一次。
        if !engine.isPlaying {
            engine.play()
        }
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        engine.layout(containerHeight: textArea.bounds.height, topRatio: 0.28)
        applyMirror()
    }

    /// 诊断用：把引擎和窗口状态拼成一行，显示在文稿列表底部
    func statusLine() -> String {
        let state = engine.isPlaying ? "滚动中" : "已暂停"
        let key = view.window?.isKeyWindow == true ? "是" : "否"
        return "引擎:\(state) 偏移:\(Int(engine.currentOffset))/\(Int(engine.scrollableDistance))"
            + " 速度:\(Int(engine.speed)) 焦点:\(key)"
    }

    func replace(script: Script) {
        self.script = script
        engine.apply(text: script.text)
        engine.reset()
        engine.play()
    }

    // MARK: - UI

    private func buildUI() {
        let settings = PrompterSettings.shared

        containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = settings.backgroundColor.withAlphaComponent(settings.bgOpacity)
        containerView.layer.cornerRadius = 14
        containerView.layer.masksToBounds = true
        containerView.layer.borderWidth = 1
        containerView.layer.borderColor = UIColor(white: 1, alpha: 0.18).cgColor
        view.addSubview(containerView)

        // 顶部拖动把：宽 32pt、横条、半透明白底 + 灰把手，让用户能明确知道
        // "这里可以拖"。pan 只挂在这里，文字区不再吃 pan，手指在文字上
        // 也不会意外触发拖动。
        dragBar = UIView()
        dragBar.translatesAutoresizingMaskIntoConstraints = false
        dragBar.backgroundColor = UIColor(white: 0.15, alpha: 0.85)
        containerView.addSubview(dragBar)

        dragBarGrip = UIView()
        dragBarGrip.translatesAutoresizingMaskIntoConstraints = false
        dragBarGrip.backgroundColor = UIColor(white: 1, alpha: 0.55)
        dragBarGrip.layer.cornerRadius = 2
        dragBar.addSubview(dragBarGrip)

        textArea = UIView()
        textArea.translatesAutoresizingMaskIntoConstraints = false
        textArea.backgroundColor = UIColor.clear
        textArea.clipsToBounds = true
        containerView.addSubview(textArea)

        engine.textView.translatesAutoresizingMaskIntoConstraints = false
        textArea.addSubview(engine.textView)

        controlBar = UIStackView()
        controlBar.translatesAutoresizingMaskIntoConstraints = false
        controlBar.axis = .horizontal
        controlBar.distribution = .fillEqually
        controlBar.alignment = .fill
        controlBar.spacing = 2
        controlBar.backgroundColor = UIColor(white: 0, alpha: 0.55)
        containerView.addSubview(controlBar)

        playButton = makeButton("⏸")
        playButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)
        controlBar.addArrangedSubview(playButton)

        let slower = makeButton("−")
        slower.addTarget(self, action: #selector(speedDown), for: .touchUpInside)
        controlBar.addArrangedSubview(slower)

        let faster = makeButton("+")
        faster.addTarget(self, action: #selector(speedUp), for: .touchUpInside)
        controlBar.addArrangedSubview(faster)

        let fontDownButton = makeButton("A−")
        fontDownButton.addTarget(self, action: #selector(decreaseFont), for: .touchUpInside)
        controlBar.addArrangedSubview(fontDownButton)

        let fontUpButton = makeButton("A+")
        fontUpButton.addTarget(self, action: #selector(increaseFont), for: .touchUpInside)
        controlBar.addArrangedSubview(fontUpButton)

        let mirror = makeButton("⇋")
        mirror.addTarget(self, action: #selector(toggleMirror), for: .touchUpInside)
        controlBar.addArrangedSubview(mirror)

        passthroughButton = makeButton("◎")
        passthroughButton.addTarget(self, action: #selector(togglePassthrough), for: .touchUpInside)
        controlBar.addArrangedSubview(passthroughButton)

        let close = makeButton("✕")
        close.setTitleColor(Theme.danger, for: .normal)
        close.addTarget(self, action: #selector(closeWindow), for: .touchUpInside)
        controlBar.addArrangedSubview(close)

        progressView = UIView()
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.backgroundColor = Theme.accent
        containerView.addSubview(progressView)

        resizeHandle = UIView()
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.backgroundColor = UIColor(white: 1, alpha: 0.25)
        resizeHandle.layer.cornerRadius = 3
        containerView.addSubview(resizeHandle)

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // 顶部拖动把
            dragBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            dragBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            dragBar.topAnchor.constraint(equalTo: containerView.topAnchor),
            dragBar.heightAnchor.constraint(equalToConstant: 32),

            // 拖动把中央的横条把手
            dragBarGrip.centerXAnchor.constraint(equalTo: dragBar.centerXAnchor),
            dragBarGrip.centerYAnchor.constraint(equalTo: dragBar.centerYAnchor),
            dragBarGrip.widthAnchor.constraint(equalToConstant: 36),
            dragBarGrip.heightAnchor.constraint(equalToConstant: 4),

            textArea.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            textArea.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            textArea.topAnchor.constraint(equalTo: dragBar.bottomAnchor, constant: 4),
            textArea.bottomAnchor.constraint(equalTo: controlBar.topAnchor),

            engine.textView.leadingAnchor.constraint(equalTo: textArea.leadingAnchor),
            engine.textView.trailingAnchor.constraint(equalTo: textArea.trailingAnchor),
            engine.textView.topAnchor.constraint(equalTo: textArea.topAnchor),
            engine.textView.bottomAnchor.constraint(equalTo: textArea.bottomAnchor),

            controlBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 6),
            controlBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -6),
            controlBar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -4),
            controlBar.heightAnchor.constraint(equalToConstant: 34),

            progressView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            progressView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2),

            // resize 手柄放大、更显眼
            resizeHandle.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -2),
            resizeHandle.bottomAnchor.constraint(equalTo: controlBar.topAnchor, constant: -2),
            resizeHandle.widthAnchor.constraint(equalToConstant: 40),
            resizeHandle.heightAnchor.constraint(equalToConstant: 10)
        ])
        progressWidthConstraint = progressView.widthAnchor.constraint(equalToConstant: 0)
        progressWidthConstraint.isActive = true

        // pan 只挂在顶部 dragBar 上，文字区完全不吃 pan
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleMove(_:)))
        dragBar.addGestureRecognizer(pan)

        let resize = UIPanGestureRecognizer(target: self, action: #selector(handleResize(_:)))
        resizeHandle.addGestureRecognizer(resize)

        engine.onProgress = { [weak self] value in
            guard let self = self else { return }
            self.progressWidthConstraint.constant = self.containerView.bounds.width * value
        }
        engine.onReachEnd = { [weak self] in
            self?.playButton.setTitle("▶", for: .normal)
        }
    }

    private func makeButton(_ title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(Theme.text, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        button.backgroundColor = UIColor(white: 1, alpha: 0.08)
        button.layer.cornerRadius = 6
        return button
    }

    private func applySettings() {
        let settings = PrompterSettings.shared
        engine.speed = settings.speed
        containerView.backgroundColor = settings.backgroundColor.withAlphaComponent(settings.bgOpacity)
        view.backgroundColor = UIColor.clear
        if isPassthrough {
            textArea.isUserInteractionEnabled = false
            (view as? PassthroughView)?.passthrough = true
        } else {
            textArea.isUserInteractionEnabled = true
            (view as? PassthroughView)?.passthrough = false
        }
    }

    private func applyMirror() {
        if PrompterSettings.shared.mirrorX {
            textArea.transform = CGAffineTransform(scaleX: -1, y: 1)
        } else {
            textArea.transform = CGAffineTransform.identity
        }
    }

    // MARK: - Actions

    @objc private func togglePlay() {
        engine.toggle()
        playButton.setTitle(engine.isPlaying ? "⏸" : "▶", for: .normal)
    }

    @objc private func speedDown() {
        let settings = PrompterSettings.shared
        settings.speed = max(5, settings.speed - 10)
        engine.speed = settings.speed
    }

    @objc private func speedUp() {
        let settings = PrompterSettings.shared
        settings.speed = min(600, settings.speed + 10)
        engine.speed = settings.speed
    }

    @objc private func decreaseFont() {
        let settings = PrompterSettings.shared
        settings.fontSize = max(14, settings.fontSize - 2)
        engine.apply(text: script.text)
    }

    @objc private func increaseFont() {
        let settings = PrompterSettings.shared
        settings.fontSize = min(96, settings.fontSize + 2)
        engine.apply(text: script.text)
    }

    @objc private func toggleMirror() {
        let settings = PrompterSettings.shared
        settings.mirrorX = !settings.mirrorX
        applyMirror()
    }

    @objc private func togglePassthrough() {
        isPassthrough = !isPassthrough
        passthroughButton.setTitle(isPassthrough ? "◉" : "◎", for: .normal)
        applySettings()
    }

    @objc private func closeWindow() {
        FloatingWindowManager.shared.hide()
    }

    // MARK: - Gestures

    @objc private func handleMove(_ gesture: UIPanGestureRecognizer) {
        guard let window = view.window else { return }
        if gesture.state == .began {
            panStartFrame = window.frame
        }
        let translation = gesture.translation(in: window)
        var frame = panStartFrame
        frame.origin.x += translation.x
        frame.origin.y += translation.y
        frame = FloatingWindowManager.clamp(frame, in: FloatingWindowManager.screenBounds())
        window.frame = frame
        if gesture.state == .ended || gesture.state == .cancelled {
            PrompterSettings.shared.floatFrame = frame
        }
    }

    @objc private func handleResize(_ gesture: UIPanGestureRecognizer) {
        guard let window = view.window else { return }
        if gesture.state == .began {
            panStartFrame = window.frame
        }
        let translation = gesture.translation(in: window)
        var frame = panStartFrame
        frame.size.width += translation.x
        frame.size.height += translation.y
        frame = FloatingWindowManager.clamp(frame, in: FloatingWindowManager.screenBounds())
        window.frame = frame
        if gesture.state == .ended || gesture.state == .cancelled {
            PrompterSettings.shared.floatFrame = frame
        }
    }
}

extension FloatingPrompterViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.view is UIButton {
            return false
        }
        return true
    }
}
