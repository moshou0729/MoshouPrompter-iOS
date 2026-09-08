import UIKit

/// 提词滚动引擎 v2 —— 虚拟滚动（视口切片）。
///
/// 为什么不用「UITextView 装全文 + 滚 contentOffset」：
/// 长文本在 UIScrollView 里会被 Core Animation 切成瓦片（tile）按需光栅化。
/// 前台 App 滚动时系统自动触发瓦片补绘；但系统级悬浮窗场景 App 处于后台，
/// 瓦片补绘不会被触发——滚到没渲染过的区域就是空白段/半截文字，
/// 而引擎进度（进度条）照常走。这就是 v1.x 一路修不掉的「到后面文字不显示」。
///
/// v2 做法：
/// - 全文用独立 TextKit 栈（NSTextStorage + NSLayoutManager + NSTextContainer）
///   离线排版，只用于坐标换算；
/// - 视口 textView 永远只装载「当前可视区间 + 上下余量」约 3 屏高的文本切片，
///   内容小、瓦片常驻，每帧只改 contentOffset（整帧提交、后台也能渲染）；
/// - 滚动位置 offset 记录在全文坐标系里，切片在余量将耗尽时才低频重建。
final class PrompterEngine: NSObject, UIGestureRecognizerDelegate {

    // MARK: - 视口

    let textView: UITextView = {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = false
        // 关键：视口不再自己滚动，所有滚动由引擎程序化驱动
        view.isScrollEnabled = false
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

    // MARK: - 全文排版栈（离线，仅做坐标换算）

    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer(
        size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))

    private var fullText: NSAttributedString = NSAttributedString(string: "")
    private var totalHeight: CGFloat = 0
    private var needsRelayout = false
    private var containerWidth: CGFloat = 0
    private var horizontalInsets: CGFloat = 0

    // MARK: - 滚动状态

    private var timer: DispatchSourceTimer?
    private var lastTimestamp: CFTimeInterval = 0
    /// 阅读线处的全文 y 坐标（0 ~ maximumOffset）
    private var offset: CGFloat = 0
    private var viewportHeight: CGFloat = 0
    private var topRatio: CGFloat = 0.35

    // MARK: - 切片状态

    private var sliceTop: CGFloat = 0       // 切片首字形在全文坐标的 y
    private var sliceHeight: CGFloat = -1   // 切片排版高度

    override init() {
        super.init()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        installPan()
        startTimer()
    }

    deinit {
        stopTimer()
    }

    // MARK: - 几何

    /// 阅读线相对视口顶部的距离
    private var readingLine: CGFloat { viewportHeight * topRatio }
    var currentOffset: CGFloat { return offset }
    var scrollableDistance: CGFloat { return maximumOffset }
    private var maximumOffset: CGFloat {
        guard totalHeight > 0, viewportHeight > 0 else { return 0 }
        return max(0, totalHeight - readingLine)
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
        fullText = NSAttributedString(string: text, attributes: attributes)
        needsRelayout = true
        relayoutIfNeeded()
        rebuildSlice(force: true)
    }

    /// 视口尺寸 / 边距变化时由调用方驱动（viewDidLayoutSubviews）
    func layout(containerHeight: CGFloat, topRatio: CGFloat = 0.35,
                horizontalInsets: CGFloat = 0) {
        guard containerHeight > 0 else { return }
        viewportHeight = containerHeight
        self.topRatio = topRatio
        horizontalInsetsChanged(horizontalInsets)
    }

    private func horizontalInsetsChanged(_ insets: CGFloat) {
        horizontalInsets = insets
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // 左右边距交给视口的左右 inset（不影响 y 坐标换算），上下恒 0
        textView.textContainerInset = UIEdgeInsets(top: 0, left: insets,
                                                   bottom: 0, right: insets)
        CATransaction.commit()
        syncContainerWidth()
    }

    private func syncContainerWidth() {
        let width = textView.bounds.width - horizontalInsets * 2
        guard width > 0 else { return }
        if abs(width - containerWidth) > 0.5 {
            containerWidth = width
            textContainer.size = CGSize(width: width,
                                        height: CGFloat.greatestFiniteMagnitude)
            needsRelayout = true
        }
        relayoutIfNeeded()
    }

    private func relayoutIfNeeded() {
        guard needsRelayout, containerWidth > 0 else { return }
        textStorage.setAttributedString(fullText)
        // 全量排版：总高度一次到位
        layoutManager.ensureLayout(for: textContainer)
        totalHeight = layoutManager.usedRect(for: textContainer).height
        needsRelayout = false
        offset = min(max(offset, 0), maximumOffset)
    }

    // MARK: - Transport

    func play() {
        guard !isPlaying else { return }
        // 已滚到末尾再按播放 = 从头开始重新滚动
        let maxOffset = maximumOffset
        if maxOffset > 0, offset >= maxOffset - 1 {
            offset = 0
            refresh(force: true)
            onProgress?(0)
        }
        isPlaying = true
        lastTimestamp = CACurrentMediaTime()
    }

    func pause() {
        isPlaying = false
    }

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    func reset() {
        offset = 0
        refresh(force: true)
        onProgress?(0)
    }

    /// 兼容保留：v2 里引擎 offset 即视口位置，无脱钩可言
    func syncOffsetFromView() {}

    var progress: CGFloat {
        let maxOffset = maximumOffset
        if maxOffset <= 0 { return 0 }
        return min(max(offset / maxOffset, 0), 1)
    }

    // MARK: - Manual scrolling

    /// 相对滚动。自动播放中也会从新位置继续，不与引擎 tick 冲突
    func scroll(by delta: CGFloat) {
        let maxOffset = maximumOffset
        offset = min(max(offset + delta, 0), maxOffset)
        refresh()
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
        refresh()
        onProgress?(maxOffset > 0 ? min(offset / maxOffset, 1) : 0)
    }

    // MARK: - 切片刷新

    private func refresh(force: Bool = false) {
        guard totalHeight > 0, viewportHeight > 0 else { return }
        if !force && sliceCoversWindow() {
            setViewOffset()
        } else {
            rebuildSlice(force: true)
        }
    }

    /// 当前可视窗口（含上下余量）是否完全落在现有切片内
    private func sliceCoversWindow() -> Bool {
        guard sliceHeight > 0 else { return false }
        let vh = viewportHeight
        let visibleTop = offset - readingLine
        return (visibleTop - vh * 0.5) >= sliceTop
            && (visibleTop + vh * 2.5) <= (sliceTop + sliceHeight)
    }

    /// 只动 contentOffset：切片内容小、瓦片常驻，后台也能整帧渲染
    private func setViewOffset() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textView.contentOffset = CGPoint(x: 0, y: offset - sliceTop)
        CATransaction.commit()
    }

    /// 重建切片：取可视窗口 ± 余量对应的文本子串装入 textView
    private func rebuildSlice(force: Bool) {
        guard totalHeight > 0, containerWidth > 0, viewportHeight > 0 else { return }
        let vh = viewportHeight
        let visibleTop = offset - readingLine
        let wantTop = max(0, visibleTop - vh * 0.5)
        let wantBottom = visibleTop + vh * 2.5
        let rect = CGRect(x: 0, y: wantTop, width: containerWidth,
                          height: max(vh, wantBottom - wantTop))
        let glyph = layoutManager.glyphRange(forBoundingRect: rect, in: textContainer)
        guard glyph.length > 0 else {
            // 空文本兜底
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            textView.attributedText = NSAttributedString(attributedString: fullText)
            textView.contentOffset = CGPoint(x: 0, y: 0)
            CATransaction.commit()
            sliceTop = 0
            sliceHeight = totalHeight
            return
        }
        let chars = layoutManager.characterRange(forGlyphRange: glyph,
                                                 actualGlyphRange: nil)
        let sub = fullText.attributedSubstring(from: chars)
        let bound = layoutManager.boundingRect(forGlyphRange: glyph, in: textContainer)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textView.attributedText = sub
        sliceTop = bound.minY
        sliceHeight = ceil(bound.height)
        textView.contentOffset = CGPoint(x: 0, y: offset - sliceTop)
        CATransaction.commit()
    }

    // MARK: - 单指拖动（视口内置手势）

    private func installPan() {
        let pan = UIPanGestureRecognizer(target: self,
                                         action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        textView.addGestureRecognizer(pan)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: textView)
        gesture.setTranslation(.zero, in: textView)
        scroll(by: -translation.y)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
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
            refresh()
            onProgress?(1)
            onReachEnd?()
            return
        }
        refresh()
        onProgress?(min(max(offset / maxOffset, 0), 1))
    }
}
