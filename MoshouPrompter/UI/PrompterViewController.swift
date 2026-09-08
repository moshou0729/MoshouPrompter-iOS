import UIKit

/// 全屏提词器
final class PrompterViewController: UIViewController {

    private let script: Script
    private let engine = PrompterEngine()

    private var topBar: UIView!
    private var bottomBar: UIView!
    private var titleLabel: UILabel!
    private var playButton: UIButton!
    private var speedLabel: UILabel!
    private var speedSlider: UISlider!
    private var fontLabel: UILabel!
    private var fontSlider: UISlider!
    private var mirrorButton: UIButton!
    private var centerLine: UIView!
    private var centerLineTopConstraint: NSLayoutConstraint!

    private var barsVisible = true
    private var hideBarsWorkItem: DispatchWorkItem?

    init(script: Script) {
        self.script = script
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var prefersStatusBarHidden: Bool { return true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { return .all }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = PrompterSettings.shared.backgroundColor
        buildTextArea()
        buildTopBar()
        buildBottomBar()
        buildCenterLine()

        engine.apply(text: script.text)
        engine.play()
        syncControls()

        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleBars))
        tap.delegate = self
        view.addGestureRecognizer(tap)

        scheduleBarsHide()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let margin = PrompterSettings.shared.margin
        // v3 引擎：视口宽高 + 左右边距都由 layout 驱动（内部离线排版换算）
        engine.layout(width: view.bounds.width,
                      containerHeight: view.bounds.height,
                      topRatio: 0.35,
                      horizontalInsets: margin)
        centerLineTopConstraint.constant = view.bounds.height * 0.35
        applyMirror()
    }

    // MARK: - Build

    private func buildTextArea() {
        engine.textView.isUserInteractionEnabled = true
        // 手动滚动由引擎内置的单指 pan 处理。
        // frame 由引擎管理（切片方案需要超出可视区的高度），不要挂 autolayout。
        view.addSubview(engine.textView)
    }

    private func buildTopBar() {
        topBar = UIView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.backgroundColor = UIColor(white: 0, alpha: 0.55)
        view.addSubview(topBar)

        titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = script.displayTitle
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textAlignment = .center
        topBar.addSubview(titleLabel)

        let close = makeBarButton("关闭")
        close.addTarget(self, action: #selector(closePrompter), for: .touchUpInside)
        topBar.addSubview(close)

        let float = makeBarButton("悬浮窗")
        float.addTarget(self, action: #selector(switchToFloating), for: .touchUpInside)
        topBar.addSubview(float)

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 88),

            titleLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -10),
            titleLabel.widthAnchor.constraint(equalToConstant: 200),

            close.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            close.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -8),
            close.widthAnchor.constraint(equalToConstant: 60),
            close.heightAnchor.constraint(equalToConstant: 32),

            float.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -12),
            float.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -8),
            float.widthAnchor.constraint(equalToConstant: 70),
            float.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    private func buildBottomBar() {
        bottomBar = UIView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.backgroundColor = UIColor(white: 0, alpha: 0.55)
        view.addSubview(bottomBar)

        playButton = makeBarButton("⏸")
        playButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)
        bottomBar.addSubview(playButton)

        let reset = makeBarButton("重置")
        reset.addTarget(self, action: #selector(resetScroll), for: .touchUpInside)
        bottomBar.addSubview(reset)

        mirrorButton = makeBarButton("镜像")
        mirrorButton.addTarget(self, action: #selector(toggleMirror), for: .touchUpInside)
        bottomBar.addSubview(mirrorButton)

        let lines = makeBarButton("参考线")
        lines.addTarget(self, action: #selector(toggleCenterLine), for: .touchUpInside)
        bottomBar.addSubview(lines)

        speedLabel = UILabel()
        speedLabel.translatesAutoresizingMaskIntoConstraints = false
        speedLabel.textColor = .white
        speedLabel.font = UIFont.systemFont(ofSize: 12)
        bottomBar.addSubview(speedLabel)

        speedSlider = UISlider()
        speedSlider.translatesAutoresizingMaskIntoConstraints = false
        speedSlider.minimumValue = 5
        speedSlider.maximumValue = 400
        speedSlider.tintColor = Theme.accent
        speedSlider.addTarget(self, action: #selector(speedChanged(_:)), for: .valueChanged)
        bottomBar.addSubview(speedSlider)

        fontLabel = UILabel()
        fontLabel.translatesAutoresizingMaskIntoConstraints = false
        fontLabel.textColor = .white
        fontLabel.font = UIFont.systemFont(ofSize: 12)
        bottomBar.addSubview(fontLabel)

        fontSlider = UISlider()
        fontSlider.translatesAutoresizingMaskIntoConstraints = false
        fontSlider.minimumValue = 16
        fontSlider.maximumValue = 96
        fontSlider.tintColor = Theme.accent
        fontSlider.addTarget(self, action: #selector(fontChanged(_:)), for: .valueChanged)
        bottomBar.addSubview(fontSlider)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 150),

            speedLabel.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 16),
            speedLabel.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 12),
            speedLabel.widthAnchor.constraint(equalToConstant: 90),

            speedSlider.leadingAnchor.constraint(equalTo: speedLabel.trailingAnchor, constant: 8),
            speedSlider.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -16),
            speedSlider.centerYAnchor.constraint(equalTo: speedLabel.centerYAnchor),

            fontLabel.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 16),
            fontLabel.topAnchor.constraint(equalTo: speedLabel.bottomAnchor, constant: 22),
            fontLabel.widthAnchor.constraint(equalToConstant: 90),

            fontSlider.leadingAnchor.constraint(equalTo: fontLabel.trailingAnchor, constant: 8),
            fontSlider.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -16),
            fontSlider.centerYAnchor.constraint(equalTo: fontLabel.centerYAnchor),

            playButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 16),
            playButton.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -18),
            playButton.widthAnchor.constraint(equalToConstant: 52),
            playButton.heightAnchor.constraint(equalToConstant: 34),

            reset.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 10),
            reset.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            reset.widthAnchor.constraint(equalToConstant: 60),
            reset.heightAnchor.constraint(equalToConstant: 34),

            mirrorButton.leadingAnchor.constraint(equalTo: reset.trailingAnchor, constant: 10),
            mirrorButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            mirrorButton.widthAnchor.constraint(equalToConstant: 60),
            mirrorButton.heightAnchor.constraint(equalToConstant: 34),

            lines.leadingAnchor.constraint(equalTo: mirrorButton.trailingAnchor, constant: 10),
            lines.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            lines.widthAnchor.constraint(equalToConstant: 70),
            lines.heightAnchor.constraint(equalToConstant: 34)
        ])
    }

    private func buildCenterLine() {
        centerLine = UIView()
        centerLine.translatesAutoresizingMaskIntoConstraints = false
        centerLine.backgroundColor = UIColor(hex: "#FF3B30").withAlphaComponent(0.35)
        centerLine.isUserInteractionEnabled = false
        view.addSubview(centerLine)
        NSLayoutConstraint.activate([
            centerLine.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            centerLine.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            centerLine.heightAnchor.constraint(equalToConstant: 1)
        ])
        centerLineTopConstraint = centerLine.topAnchor.constraint(equalTo: view.topAnchor, constant: 0)
        centerLineTopConstraint.isActive = true
        centerLine.isHidden = !PrompterSettings.shared.centerLine
    }

    private func makeBarButton(_ title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        button.backgroundColor = UIColor(white: 1, alpha: 0.12)
        button.layer.cornerRadius = 8
        return button
    }

    // MARK: - Sync

    private func syncControls() {
        let settings = PrompterSettings.shared
        engine.speed = settings.speed
        speedSlider.value = Float(settings.speed)
        fontSlider.value = Float(settings.fontSize)
        speedLabel.text = "速度 \(Int(settings.speed))"
        fontLabel.text = "字号 \(Int(settings.fontSize))"
        playButton.setTitle(engine.isPlaying ? "⏸" : "▶", for: .normal)
        mirrorButton.setTitle(settings.mirrorX ? "镜像✓" : "镜像", for: .normal)
    }

    private func applyMirror() {
        // v3 引擎自己用 transform 做滚动微移，镜像交给引擎合成
        engine.mirrorX = PrompterSettings.shared.mirrorX
    }

    // MARK: - Actions

    @objc private func togglePlay() {
        engine.toggle()
        playButton.setTitle(engine.isPlaying ? "⏸" : "▶", for: .normal)
        scheduleBarsHide()
    }

    @objc private func resetScroll() {
        engine.reset()
        scheduleBarsHide()
    }

    @objc private func toggleMirror() {
        let settings = PrompterSettings.shared
        settings.mirrorX = !settings.mirrorX
        applyMirror()
        syncControls()
        scheduleBarsHide()
    }

    @objc private func toggleCenterLine() {
        let settings = PrompterSettings.shared
        settings.centerLine = !settings.centerLine
        centerLine.isHidden = !settings.centerLine
        scheduleBarsHide()
    }

    @objc private func speedChanged(_ slider: UISlider) {
        let settings = PrompterSettings.shared
        settings.speed = CGFloat(slider.value)
        engine.speed = settings.speed
        speedLabel.text = "速度 \(Int(settings.speed))"
        scheduleBarsHide()
    }

    @objc private func fontChanged(_ slider: UISlider) {
        let settings = PrompterSettings.shared
        settings.fontSize = CGFloat(slider.value)
        engine.apply(text: script.text)
        fontLabel.text = "字号 \(Int(settings.fontSize))"
        scheduleBarsHide()
    }

    @objc private func closePrompter() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func switchToFloating() {
        dismiss(animated: true, completion: {
            FloatingWindowManager.shared.show(script: self.script)
        })
    }

    @objc private func toggleBars() {
        setBarsVisible(!barsVisible)
        if barsVisible { scheduleBarsHide() }
    }

    private func setBarsVisible(_ visible: Bool) {
        barsVisible = visible
        UIView.animate(withDuration: 0.22, animations: {
            self.topBar.alpha = visible ? 1 : 0
            self.bottomBar.alpha = visible ? 1 : 0
        }, completion: nil)
    }

    private func scheduleBarsHide() {
        hideBarsWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.setBarsVisible(false)
        }
        hideBarsWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 4, execute: item)
    }
}

extension PrompterViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.view is UIControl {
            return false
        }
        return true
    }
}
