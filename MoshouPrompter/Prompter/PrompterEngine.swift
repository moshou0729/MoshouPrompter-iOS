import UIKit

/// 提词滚动引擎：持有一个 UITextView，用 GCD 定时器按「点/秒」匀速上滚。
/// 用 DispatchSourceTimer 而不是 CADisplayLink，是因为系统级悬浮窗场景下
/// App 处于非活跃状态，CADisplayLink 会被系统暂停，而 GCD 定时器不会。
final class PrompterEngine {

    let textView: UITextView = {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = true
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        view.alwaysBounceVertical = false
        view.backgroundColor = UIColor.clear
        view.textContainer.lineFragmentPadding = 0
        view.textContainerInset = UIEdgeInsets.zero
        view.contentInset = UIEdgeInsets.zero
        view.indicatorStyle = .white
        return view
    }()

    var speed: CGFloat = 55 {
        didSet { speed = max(0, speed) }
    }

    var isPlaying: Bool = false

    /// 0 ~ 1
    var onProgress: ((CGFloat) -> Void)?
    var onReachEnd: (() -> Void)?

    private var timer: DispatchSourceTimer?
    private var lastTimestamp: CFTimeInterval = 0
    private var offset: CGFloat = 0

    init() {
        startTimer()
    }

    deinit {
        stopTimer()
    }

    // MARK: - Content

    func apply(text: String) {
        let settings = PrompterSettings.shared
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = settings.lineSpacing
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: settings.fontSize, weight: .medium),
            .foregroundColor: settings.textColor,
            .paragraphStyle: paragraph
        ]
        let previous = offset
        textView.attributedText = NSAttributedString(string: text, attributes: attributes)
        offset = previous
        textView.contentOffset = CGPoint(x: 0, y: offset)
    }

    /// 上下留白让首行停在阅读线、末行能滚到阅读线
    func layout(containerHeight: CGFloat, topRatio: CGFloat = 0.35) {
        guard containerHeight > 0 else { return }
        // 上下内边距都取 topRatio，二者之和 < 容器高度，
        // 文本容器高度保持为正，文字才能正常排版、才能滚动。
        // 旧实现 bottom = 1-topRatio，二者之和 = 容器高度 → 容器 0 高 → 不滚动。
        let inset = containerHeight * topRatio
        textView.textContainerInset = UIEdgeInsets(top: inset,
                                                   left: 0,
                                                   bottom: inset,
                                                   right: 0)
    }

    // MARK: - Transport

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        lastTimestamp = CACurrentMediaTime()
    }

    func pause() {
        isPlaying = false
    }

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    /// 只读快照，给诊断显示用
    var currentOffset: CGFloat { return offset }
    var scrollableDistance: CGFloat { return maximumOffset }

    // MARK: - Manual scrolling（手动滚动：▲▼ 按钮 / 双指拖动）

    /// 相对滚动。自动播放中也会从新位置继续，不与引擎 tick 冲突
    /// （tick 基于 offset 递增，这里直接改 offset）。
    func scroll(by delta: CGFloat) {
        let maxOffset = maximumOffset
        offset = min(max(offset + delta, 0), maxOffset)
        textView.contentOffset = CGPoint(x: 0, y: offset)
        onProgress?(maxOffset > 0 ? min(offset / maxOffset, 1) : 0)
        if maxOffset > 0, offset >= maxOffset, isPlaying {
            isPlaying = false
            onReachEnd?()
        }
    }

    /// 绝对定位（双指拖动用）
    func setOffset(_ y: CGFloat) {
        let maxOffset = maximumOffset
        offset = min(max(y, 0), maxOffset)
        textView.contentOffset = CGPoint(x: 0, y: offset)
        onProgress?(maxOffset > 0 ? min(offset / maxOffset, 1) : 0)
    }

    func reset() {
        offset = 0
        textView.contentOffset = CGPoint(x: 0, y: 0)
        onProgress?(0)
    }

    /// 用户手动滚动后把外部偏移同步回引擎
    func syncOffsetFromView() {
        offset = textView.contentOffset.y
    }

    var progress: CGFloat {
        let maxOffset = maximumOffset
        if maxOffset <= 0 { return 0 }
        return min(max(offset / maxOffset, 0), 1)
    }

    private var maximumOffset: CGFloat {
        return max(0, textView.contentSize.height - textView.bounds.height)
    }

    // MARK: - Timer

    private func startTimer() {
        let source = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        source.schedule(deadline: DispatchTime.now(), repeating: .milliseconds(16))
        source.setEventHandler { [weak self] in
            self?.tick()
        }
        source.resume()
        timer = source
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        guard isPlaying else {
            lastTimestamp = CACurrentMediaTime()
            return
        }
        let now = CACurrentMediaTime()
        let delta = min(max(now - lastTimestamp, 0), 0.1)
        lastTimestamp = now

        let maxOffset = maximumOffset
        // 布局还没完成 / 文本太短时 maxOffset 会是 0，
        // 这里绝对不能据此判定「滚到底了」——否则引擎会在第一次 tick 就永久停机。
        guard maxOffset > 0 else {
            onProgress?(0)
            return
        }

        offset += speed * CGFloat(delta)
        if offset >= maxOffset {
            offset = maxOffset
            isPlaying = false
            textView.contentOffset = CGPoint(x: 0, y: offset)
            onProgress?(1)
            onReachEnd?()
            return
        }
        textView.contentOffset = CGPoint(x: 0, y: offset)
        if maxOffset > 0 {
            onProgress?(min(max(offset / maxOffset, 0), 1))
        }
    }
}
