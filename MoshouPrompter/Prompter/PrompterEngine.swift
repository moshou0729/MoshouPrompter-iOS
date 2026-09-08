import UIKit

/// 提词滚动引擎 v3 —— 单屏切片 + transform 微移。
///
/// v1.x 教训：UITextView 装全文滚 contentOffset，长内容被 Core Animation 切成
/// 瓦片按需光栅化；系统级悬浮窗下 App 在后台，瓦片补绘不触发 → 滚到没渲染过
/// 的区域就是空白段/半截字。
///
/// v1.1.10 教训：视口关了 isScrollEnabled 却仍用 contentOffset 驱动——iOS 会把
/// 关滚动 UITextView 的 contentOffset 钳回 0，结果永远只显示切片顶部第一行。
///
/// v3 彻底不「滚动」：
/// - 全文用独立 TextKit 栈离线排版，只做坐标换算；
/// - 视口 textView 永远只装「当前可视区间 + 一行余量」的切片，内容不超过
///   自身 frame，contentSize == frame，完全绕开瓦片机制——整帧一次绘制，
///   后台也能可靠渲染；
/// - 行内平滑移动用 textView.transform 平移（纯合成器操作，不触发重绘）；
///   移动满一行后低频重建切片。
final class PrompterEngine: NSObject, UIGestureRecognizerDelegate {

    // MARK: - 视口

    /// frame 由引擎在 layout(width:containerHeight:) 里直接管理，
    /// 不要给它挂 autolayout 约束。
    let textView: UITextView = {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = false
        // 关键：视口永远不滚动。所有位移由 transform 完成。
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

    /// 水平镜像。v3 起由引擎合成进 transform（引擎自己用 transform 做滚动微移，
    /// 外部不能再直接改 textView.transform，否则会互相覆盖）
    var mirrorX: Bool = false

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
    /// 单行高度（含行距），由排版结果实测
    private var lineHeight: CGFloat = 30

    // MARK: - 滚动状态

    private var timer: DispatchSourceTimer?
    private var lastTimestamp: CFTimeInterval = 0
    /// 阅读线处的全文 y 坐标（0 ~ maximumOffset）
    private var offset: CGFloat = 0
    private var viewportHeight: CGFloat = 0
    private var viewportWidth: CGFloat = 0
    private var topRatio: CGFloat = 0.28

    // MARK: - 切片状态

    private var sliceTop: CGFloat = -1      // 切片首行顶在全文坐标的 y
    private var sliceBottom: CGFloat = -1   // 切片末行底在全文坐标的 y

    override init() {
        super.init()
        // 离线栈与视口必须同参排版：padding 同为 0，坐标 1:1 对应
        textContainer.lineFragmentPadding = 0
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
        refresh(force: true)
    }

    /// 视口尺寸变化时由调用方驱动（viewDidLayoutSubviews）。
    /// textView 的 frame 在这里统一设置：高 = 视口高 + 上下余量。
    func layout(width: CGFloat, containerHeight: CGFloat, topRatio: CGFloat = 0.28,
                horizontalInsets: CGFloat = 0) {
        guard width > 0, containerHeight > 0 else { return }
        viewportWidth = width
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
        let width = viewportWidth - horizontalInsets * 2
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
        measureLineHeight()
        updateFrameIfNeeded()
    }

    /// 用第一行实测行高（含行距），决定切片余量与视口 frame 高度
    private func measureLineHeight() {
        guard fullText.length > 0 else { return }
        let rect = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        if rect.height > 1 {
            lineHeight = rect.height
        }
    }

    /// textView frame 高度 = 视口 + 上下各一行余量。
    /// 切片内容（可视区间 + 下方一行余量）永远装得下，
    /// contentSize == frame → 无瓦片 → 后台整帧绘制可靠。
    private func updateFrameIfNeeded() {
        guard viewportWidth > 0, viewportHeight > 0 else { return }
        let h = viewportHeight + lineHeight * 2 + 24
        let f = CGRect(x: 0, y: 0, width: viewportWidth, height: h)
        if textView.frame != f {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            textView.frame = f
            CATransaction.commit()
        }
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

    /// 兼容保留：v3 里引擎 offset 即视口位置，无脱钩可言
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
        guard totalHeight > 0, viewportHeight > 0, viewportWidth > 0 else { return }
        let visTop = max(0, offset - readingLine)
        // 末尾时可视窗口底部会超出全文（阅读线在 28% 处），比较时截到全文底
        let visBottom = min(visTop + viewportHeight, totalHeight)
        let needsRebuild = force
            || sliceTop < 0
            || visTop < sliceTop
            || visTop - sliceTop >= lineHeight
            || visBottom > sliceBottom
        if needsRebuild {
            rebuildSlice(visTop: visTop)
        }
        // 行内微移：切片首行顶相对可视顶的差，用 transform 平移补偿。
        // 纯合成器变换，不触发任何重绘，后台照样流畅。
        let t = max(0, min(visTop - sliceTop, lineHeight * 2))
        var xform = CGAffineTransform(translationX: 0, y: -t)
        if mirrorX {
            xform = xform.scaledBy(x: -1, y: 1)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textView.transform = xform
        CATransaction.commit()
    }

    /// 重建切片：把 [visTop, visTop + 视口高 + 一行余量] 的文本整帧装入 textView
    private func rebuildSlice(visTop: CGFloat) {
        guard totalHeight > 0, containerWidth > 0 else { return }
        let margin = lineHeight + 8
        let wantTop = max(0, visTop)
        let wantBottom = min(totalHeight, visTop + viewportHeight + margin)
        let rect = CGRect(x: 0, y: wantTop, width: containerWidth,
                          height: max(1, wantBottom - wantTop))
        let glyph = layoutManager.glyphRange(forBoundingRect: rect, in: textContainer)
        guard glyph.length > 0 else {
            // 空文本兜底
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            textView.attributedText = NSAttributedString(attributedString: fullText)
            textView.transform = .identity
            CATransaction.commit()
            sliceTop = 0
            sliceBottom = totalHeight
            return
        }
        let chars = layoutManager.characterRange(forGlyphRange: glyph,
                                                 actualGlyphRange: nil)
        let sub = fullText.attributedSubstring(from: chars)
        let bound = layoutManager.boundingRect(forGlyphRange: glyph, in: textContainer)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textView.attributedText = sub
        CATransaction.commit()
        // bound.minY 是包含 visTop 那一行的行顶（≤ visTop），
        // 与视口首行保持整行对齐，transform 负责行内的部分
        sliceTop = bound.minY
        sliceBottom = bound.maxY
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
