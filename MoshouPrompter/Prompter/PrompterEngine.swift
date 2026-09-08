import UIKit

/// 提词滚动引擎：持有一个 UITextView，用 GCD 定时器按「点/秒」匀速上滚。
/// 用 DispatchSourceTimer 而不是 CADisplayLink，是因为系统级悬浮窗场景下
/// App 处于非活跃状态，CADisplayLink 会被系统暂停，而 GCD 定时器不会。
///
/// offset 的唯一可信来源是 textView 的实际 contentOffset：
/// - play() 时先从 view 同步，保证「从你看到的位置继续滚」，不会跳到引擎记的旧位置；
/// - textViewDidScroll 实时回写，覆盖原生滑动与 UIKit 自动调整 contentOffset 的情况。
final class PrompterEngine: NSObject, UITextViewDelegate {

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

    override init() {
        super.init()
        // 引擎自己当 scrollView delegate：实时掌握 view 的真实滚动位置。
        // 当前没有其他地方占用 textView.delegate（已确认）。
        textView.delegate = self
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
        // 关键修复：从 textView 的真实位置续播。引擎内部 offset 可能因
        // UIKit 布局调整 contentOffset、原生滑动等已与显示位置脱钩
        // （表现：手动翻回顶部后按播放，直接跳到内容末尾）。
        let maxOffset = maximumOffset
        offset = min(max(textView.contentOffset.y, 0), maxOffset)
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

    // MARK: - UITextViewDelegate

    /// view 的真实滚动位置实时回写引擎。覆盖三类来源：
    /// 1. 原生单指滑动（穿透关闭时 / 全屏提词页）
    /// 2. UIKit 因内边距变化、布局等自动调整 contentOffset
    /// 3. 引擎自己程序化设置（幂等，无副作用）
    /// 若 UIKit 对程序化设置做了 clamp，这里会把 offset 拉回 view 实际值——自愈。
    /// 必须显式 @objc：UITextViewDelegate 的可选方法若未暴露给 ObjC，
    /// 运行时 respondsToSelector 不命中，本方法永远不会被调用。
    @objc private func textViewDidScroll(_ scrollView: UITextView) {
        offset = scrollView.contentOffset.y
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
