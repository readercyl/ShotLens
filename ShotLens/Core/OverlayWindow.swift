import AppKit
import CoreGraphics

enum OverlayGeometry {
    static let minimumReadableSize = CGSize(width: 120, height: 44)

    static func resultFrame(
        screenshotPixelSize: CGSize,
        screenPosition: CGPoint,
        displayScale: CGFloat
    ) -> CGRect {
        let scale = max(displayScale, 1.0)
        let imageSize = CGSize(
            width: screenshotPixelSize.width / scale,
            height: screenshotPixelSize.height / scale
        )
        return CGRect(origin: screenPosition, size: imageSize)
    }
}

/// 原位翻译结果层：选区内显示截图与译文，选区外点击即结束本次截图。
final class OverlayWindow: NSObject, NSWindowDelegate {
    var onDismiss: (() -> Void)?
    var onRetry: (() -> Void)?
    var onRetranslate: (() -> Void)?

    fileprivate static let backdropLevel = NSWindow.Level.screenSaver
    fileprivate static let resultLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
    fileprivate static let controlLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
    fileprivate static let fullscreenOverlayBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .stationary,
        .ignoresCycle
    ]

    private var resultWindow: OverlayResultWindow?
    private var statusWindow: OverlayStatusWindow?
    private var saveWindow: OverlaySaveWindow?
    private var backdropWindows: [OverlayBackdropWindow] = []
    private var contentView: OverlayContentView?
    private var outsideClickMonitor: Any?
    private var didDismiss = false
    private var isShowingTranslation = true
    private var isPinned = false
    private var isRetranslating = false
    private var controlPhase: OverlayControlPhase = .processing

    func show(
        croppedScreenshot: CGImage,
        at screenPosition: CGPoint,
        displayScale: CGFloat
    ) {
        let scale = max(displayScale, 1.0)
        let windowRect = OverlayGeometry.resultFrame(
            screenshotPixelSize: CGSize(width: croppedScreenshot.width, height: croppedScreenshot.height),
            screenPosition: screenPosition,
            displayScale: scale
        )

        backdropWindows = makeBackdropWindows()
        startOutsideClickMonitor()

        let window = OverlayResultWindow(
            contentRect: windowRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = Self.resultLevel
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.collectionBehavior = Self.fullscreenOverlayBehavior
        window.delegate = self
        window.onCancel = { [weak self] in
            self?.dismiss()
        }

        let contentView = OverlayContentView(frame: NSRect(origin: .zero, size: windowRect.size))
        contentView.screenshot = croppedScreenshot
        contentView.displayScale = scale
        contentView.onTogglePin = { [weak self] in
            self?.togglePinned()
        }
        window.contentView = contentView

        let statusWindow = OverlayStatusWindow(anchorRect: windowRect)
        statusWindow.setMessage("正在识别")

        self.resultWindow = window
        self.statusWindow = statusWindow
        self.contentView = contentView

        backdropWindows.forEach { $0.orderFrontRegardless() }
        window.orderFrontRegardless()
        statusWindow.orderFrontRegardless()
    }

    @MainActor
    func setProcessing(_ message: String) {
        controlPhase = .processing
        isShowingTranslation = true
        contentView?.setTranslatedBlocks([])
        contentView?.setDisplayMode(.translation)
        statusWindow?.setMessage(message.shortStatusText)
        closeSaveWindow()
        applyControlVisibility()
    }

    @MainActor
    func setTranslatedBlocks(_ blocks: [TranslatedBlock]) {
        controlPhase = .success
        isRetranslating = false
        isShowingTranslation = true
        contentView?.setTranslatedBlocks(blocks)
        contentView?.setDisplayMode(.translation)
        setToggleStatus(message: "翻译完成")
    }

    @MainActor
    func setMessage(_ message: String) {
        controlPhase = message.contains("失败") ? .failure : .processing
        isRetranslating = false
        isShowingTranslation = true
        contentView?.setTranslatedBlocks([])
        contentView?.setDisplayMode(.translation)
        if message.contains("失败") {
            closeSaveWindow()
            statusWindow?.setFailure(message: message, retryTitle: "重新翻译") { [weak self] in
                self?.onRetry?()
            }
        } else {
            statusWindow?.setMessage(message)
            closeSaveWindow()
        }
        applyControlVisibility()
    }

    private func makeBackdropWindows() -> [OverlayBackdropWindow] {
        NSScreen.screens.map { screen in
            let window = OverlayBackdropWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.level = Self.backdropLevel
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.animationBehavior = .none
            window.isReleasedWhenClosed = false
            window.collectionBehavior = Self.fullscreenOverlayBehavior
            window.onCancel = { [weak self] in
                self?.dismiss()
            }
            let view = OverlayBackdropView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onClose = { [weak self] in
                self?.dismissFromOutsideClick()
            }
            window.contentView = view
            return window
        }
    }

    private func startOutsideClickMonitor() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let resultWindow = self.resultWindow else { return }
                let mouseLocation = NSEvent.mouseLocation
                if resultWindow.frame.contains(mouseLocation) {
                    return
                }
                if self.statusWindow?.frame.contains(mouseLocation) == true {
                    return
                }
                if self.saveWindow?.frame.contains(mouseLocation) == true {
                    return
                }
                self.dismissFromOutsideClick()
            }
        }
    }

    private func dismiss() {
        resultWindow?.close()
        if resultWindow == nil {
            closeBackdropWindows()
            finishDismiss()
        }
    }

    private func dismissFromOutsideClick() {
        guard !isPinned else { return }
        dismiss()
    }

    private func togglePinned() {
        isPinned.toggle()
        contentView?.setPinned(isPinned)
        applyControlVisibility()
    }

    @MainActor
    private func beginRetranslation() {
        guard !isRetranslating else { return }
        isRetranslating = true
        setProcessing("正在重新翻译...")
        onRetranslate?()
    }

    func windowWillClose(_ notification: Notification) {
        resultWindow = nil
        statusWindow?.close()
        statusWindow = nil
        saveWindow?.close()
        saveWindow = nil
        contentView = nil
        closeBackdropWindows()
        finishDismiss()
    }

    private func closeBackdropWindows() {
        let windows = backdropWindows
        backdropWindows = []
        windows.forEach { $0.close() }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    private func closeSaveWindow() {
        saveWindow?.close()
        saveWindow = nil
    }

    private func finishDismiss() {
        guard !didDismiss else { return }
        didDismiss = true
        let callback = onDismiss
        onDismiss = nil
        onRetry = nil
        onRetranslate = nil
        callback?()
    }

    func windowDidMove(_ notification: Notification) {
        guard let resultWindow else { return }
        statusWindow?.updateAnchorRect(resultWindow.frame)
        if let statusWindow {
            saveWindow?.updateStatusFrame(statusWindow.frame)
        }
    }

    @MainActor
    private func toggleOriginalAndTranslation() {
        isShowingTranslation.toggle()
        if isShowingTranslation {
            contentView?.setDisplayMode(.translation)
            setToggleStatus(message: "翻译完成")
        } else {
            contentView?.setDisplayMode(.original)
            setToggleStatus(message: "显示原文")
        }
    }

    @MainActor
    private func copyCurrentSnapshotToClipboard() {
        guard let contentView,
              let image = contentView.renderToImage() else {
            return
        }
        let text = contentView.translatedBlocks
            .map(\.translatedText)
            .joined(separator: "\n")
        ClipboardManager().copyToClipboard(image: image, text: text)
        ShotLensLogger.log("截图已保存到剪贴板")
        dismiss()
    }

    @MainActor
    private func copyTranslatedTextToClipboard() {
        guard let contentView else { return }
        let text = contentView.translatedBlocks
            .map(\.translatedText)
            .joined(separator: "\n")
        ClipboardManager().copyTextToClipboard(text)
        setToggleStatus(message: "已复制译文")
    }

    @MainActor
    private func setToggleStatus(message: String) {
        statusWindow?.setToggle(
            message: message,
            toggleTitle: isShowingTranslation ? "显示原文" : "显示翻译",
            onToggle: { [weak self] in
                self?.toggleOriginalAndTranslation()
            }
        )
        showSaveWindow()
        applyControlVisibility()
    }

    private func applyControlVisibility() {
        let visibility = OverlayControlVisibility.resolve(phase: controlPhase, pinned: isPinned)
        if visibility.statusVisible {
            statusWindow?.orderFrontRegardless()
        } else {
            statusWindow?.orderOut(nil)
        }
        if visibility.actionsVisible {
            saveWindow?.orderFrontRegardless()
        } else {
            saveWindow?.orderOut(nil)
        }
    }

    @MainActor
    private func showSaveWindow() {
        guard let statusWindow else { return }
        if let saveWindow {
            saveWindow.updateStatusFrame(statusWindow.frame)
            saveWindow.orderFrontRegardless()
            return
        }
        let window = OverlaySaveWindow(statusFrame: statusWindow.frame)
        window.onCopyText = { [weak self] in
            self?.copyTranslatedTextToClipboard()
        }
        window.onSave = { [weak self] in
            self?.copyCurrentSnapshotToClipboard()
        }
        window.onRetranslate = { [weak self] in
            self?.beginRetranslation()
        }
        saveWindow = window
        window.orderFrontRegardless()
    }
}

private final class OverlayStatusWindow: NSPanel {
    private var anchorRect: CGRect
    private let statusView: StatusContentView

    init(anchorRect: CGRect) {
        self.anchorRect = anchorRect
        self.statusView = StatusContentView(frame: CGRect(x: 0, y: 0, width: 76, height: 28))
        super.init(
            contentRect: CGRect(origin: anchorRect.origin, size: statusView.bounds.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = OverlayWindow.controlLevel
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        collectionBehavior = OverlayWindow.fullscreenOverlayBehavior
        contentView = statusView
    }

    override var canBecomeKey: Bool { true }

    func setMessage(_ message: String) {
        ignoresMouseEvents = true
        statusView.setMessage(message)
        let size = statusView.preferredSize
        statusView.frame = CGRect(origin: .zero, size: size)
        setFrame(statusFrame(size: size), display: true)
    }

    func setFailure(message: String, retryTitle: String, onRetry: @escaping () -> Void) {
        ignoresMouseEvents = false
        statusView.setFailure(message: message, retryTitle: retryTitle, onRetry: onRetry)
        let size = statusView.preferredSize
        statusView.frame = CGRect(origin: .zero, size: size)
        setFrame(statusFrame(size: size), display: true)
        orderFrontRegardless()
    }

    func setToggle(
        message: String,
        toggleTitle: String,
        onToggle: @escaping () -> Void
    ) {
        ignoresMouseEvents = false
        statusView.setToggle(
            message: message,
            toggleTitle: toggleTitle,
            onToggle: onToggle
        )
        let size = statusView.preferredSize
        statusView.frame = CGRect(origin: .zero, size: size)
        setFrame(statusFrame(size: size), display: true)
        orderFrontRegardless()
    }

    func updateAnchorRect(_ rect: CGRect) {
        anchorRect = rect
        let size = statusView.preferredSize
        setFrame(statusFrame(size: size), display: true)
    }

    private func statusFrame(size: CGSize) -> CGRect {
        let gap: CGFloat = 8
        let screenFrame = NSScreen.screens.first { $0.frame.intersects(anchorRect) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? anchorRect
        let x = min(max(anchorRect.midX - size.width / 2, screenFrame.minX + 8), screenFrame.maxX - size.width - 8)
        let yBelow = anchorRect.minY - gap - size.height
        let y = yBelow >= screenFrame.minY
            ? yBelow
            : min(screenFrame.maxY - size.height - 8, anchorRect.maxY + gap)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

private final class OverlaySaveWindow: NSPanel {
    var onCopyText: (() -> Void)? {
        didSet { saveView.onCopyText = onCopyText }
    }

    var onSave: (() -> Void)? {
        didSet { saveView.onSave = onSave }
    }

    var onRetranslate: (() -> Void)? {
        didSet { saveView.onRetranslate = onRetranslate }
    }

    private let saveView = StatusActionButtonsView(frame: CGRect(x: 0, y: 0, width: 100, height: 28))

    init(statusFrame: CGRect) {
        super.init(
            contentRect: Self.frame(for: statusFrame),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = OverlayWindow.controlLevel
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        collectionBehavior = OverlayWindow.fullscreenOverlayBehavior
        contentView = saveView
    }

    override var canBecomeKey: Bool { true }

    func updateStatusFrame(_ statusFrame: CGRect) {
        setFrame(Self.frame(for: statusFrame), display: true)
    }

    private static func frame(for statusFrame: CGRect) -> CGRect {
        let gap: CGFloat = 8
        let size = CGSize(width: 100, height: 28)
        let screenFrame = NSScreen.screens.first { $0.frame.intersects(statusFrame) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? statusFrame
        let preferredX = statusFrame.maxX + gap
        let fallbackX = statusFrame.minX - gap - size.width
        let x = preferredX + size.width <= screenFrame.maxX - 8
            ? preferredX
            : max(screenFrame.minX + 8, fallbackX)
        let y = min(max(statusFrame.midY - size.height / 2, screenFrame.minY + 8), screenFrame.maxY - size.height - 8)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

private final class StatusContentView: NSView {
    private var message = ""
    private let retryButton = StatusRetryButton()

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    var preferredSize: CGSize {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium)
        ]
        let textSize = (message as NSString).size(withAttributes: attrs)
        let buttonWidth: CGFloat = retryButton.isHidden ? 0 : retryButton.preferredWidth
        let gap: CGFloat = retryButton.isHidden ? 0 : 8
        return CGSize(
            width: min(max(58, ceil(textSize.width) + 22 + buttonWidth + gap), 190),
            height: 28
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        retryButton.isHidden = true
        addSubview(retryButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setMessage(_ message: String) {
        self.message = message
        retryButton.isHidden = true
        retryButton.onClick = nil
        needsLayout = true
        needsDisplay = true
    }

    func setFailure(message: String, retryTitle: String, onRetry: @escaping () -> Void) {
        self.message = message
        retryButton.title = retryTitle
        retryButton.isHidden = false
        retryButton.onClick = onRetry
        needsLayout = true
        needsDisplay = true
    }

    func setToggle(
        message: String,
        toggleTitle: String,
        onToggle: @escaping () -> Void
    ) {
        self.message = message
        retryButton.title = toggleTitle
        retryButton.isHidden = false
        retryButton.onClick = onToggle
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        if !retryButton.isHidden {
            let width = retryButton.preferredWidth
            retryButton.frame = NSRect(x: bounds.maxX - width - 8, y: 4, width: width, height: 20)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = (message as NSString).size(withAttributes: attrs)
        let textMaxX = retryButton.isHidden ? bounds.maxX : retryButton.frame.minX - 8
        let textMidX = (bounds.minX + textMaxX) / 2
        let point = CGPoint(
            x: textMidX - textSize.width / 2,
            y: bounds.midY - textSize.height / 2
        )
        (message as NSString).draw(at: point, withAttributes: attrs)
    }
}

private final class StatusRetryButton: NSControl {
    var title = "重新翻译" {
        didSet { needsDisplay = true }
    }
    var onClick: (() -> Void)?

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(
            at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attrs
        )
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

private final class StatusActionButtonsView: NSView {
    var onCopyText: (() -> Void)? {
        didSet { copyTextButton.onCopyText = onCopyText }
    }

    var onSave: (() -> Void)? {
        didSet { saveButton.onSave = onSave }
    }

    var onRetranslate: (() -> Void)? {
        didSet { retranslateButton.onRetranslate = onRetranslate }
    }

    private let copyTextButton = StatusCopyTextButton(frame: CGRect(x: 0, y: 0, width: 28, height: 28))
    private let retranslateButton = StatusRetranslateButton(frame: CGRect(x: 36, y: 0, width: 28, height: 28))
    private let saveButton = StatusSaveButton(frame: CGRect(x: 72, y: 0, width: 28, height: 28))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        copyTextButton.toolTip = "复制译文"
        retranslateButton.toolTip = "重新翻译"
        saveButton.toolTip = "复制截图"
        addSubview(copyTextButton)
        addSubview(retranslateButton)
        addSubview(saveButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        copyTextButton.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
        retranslateButton.frame = CGRect(x: 36, y: 0, width: 28, height: 28)
        saveButton.frame = CGRect(x: bounds.maxX - 28, y: 0, width: 28, height: 28)
    }
}

private final class StatusRetranslateButton: NSControl {
    var onRetranslate: (() -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.58).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        let text = "↻" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) { onRetranslate?() }
}

private final class StatusCopyTextButton: NSControl {
    var onCopyText: (() -> Void)?

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.58).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        drawCopyIcon()
    }

    private func drawCopyIcon() {
        NSColor.white.setStroke()
        let back = NSBezierPath(roundedRect: CGRect(x: bounds.midX - 5, y: bounds.midY - 3, width: 9, height: 10), xRadius: 2, yRadius: 2)
        back.lineWidth = 1.7
        back.stroke()
        let front = NSBezierPath(roundedRect: CGRect(x: bounds.midX - 2, y: bounds.midY - 6, width: 9, height: 10), xRadius: 2, yRadius: 2)
        front.lineWidth = 1.7
        front.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        onCopyText?()
    }
}

private final class StatusSaveButton: NSControl {
    var onSave: (() -> Void)?

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    var preferredWidth: CGFloat { 24 }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.58).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        drawSaveIcon()
    }

    private func drawSaveIcon() {
        let path = NSBezierPath()
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: bounds.midX - 5, y: bounds.midY - 1))
        path.line(to: NSPoint(x: bounds.midX - 1.5, y: bounds.midY - 4))
        path.line(to: NSPoint(x: bounds.midX + 6, y: bounds.midY + 5))
        NSColor.white.setStroke()
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        onSave?()
    }
}

private extension StatusRetryButton {
    var preferredWidth: CGFloat {
        max(46, min(78, ceil((title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium)
        ]).width) + 18))
    }
}

private final class OverlayResultWindow: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }
}

private final class OverlayBackdropWindow: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }
}

private final class OverlayBackdropView: NSView {
    var onClose: (() -> Void)?

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        onClose?()
    }
}

final class OverlayContentView: NSView {
    var onTogglePin: (() -> Void)?
    var screenshot: CGImage? {
        didSet { updatePinContrast() }
    }
    var displayScale: CGFloat = 1.0
    var translatedBlocks: [TranslatedBlock] = []
    private var displayMode: OverlayDisplayMode = .translation
    private let pinButton = OverlayPinButton(frame: CGRect(x: 0, y: 0, width: 24, height: 24))

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupControls()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setTranslatedBlocks(_ blocks: [TranslatedBlock]) {
        translatedBlocks = blocks
        needsDisplay = true
    }

    func setPinned(_ pinned: Bool) {
        pinButton.isPinned = pinned
    }

    fileprivate func setDisplayMode(_ mode: OverlayDisplayMode) {
        displayMode = mode
        needsDisplay = true
    }

    private func setupControls() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        pinButton.toolTip = "钉住浮框"
        pinButton.onClick = { [weak self] in self?.onTogglePin?() }
        addSubview(pinButton)
    }

    override func layout() {
        super.layout()
        pinButton.frame = CGRect(x: max(4, bounds.maxX - 28), y: 4, width: 24, height: 24)
        updatePinContrast()
    }

    private func updatePinContrast() {
        guard let screenshot, bounds.width > 0, bounds.height > 0 else { return }
        let scaleX = CGFloat(screenshot.width) / bounds.width
        let scaleY = CGFloat(screenshot.height) / bounds.height
        let sampleRect = CGRect(
            x: max(0, CGFloat(screenshot.width) - 28 * scaleX),
            y: max(0, 4 * scaleY),
            width: min(CGFloat(screenshot.width), 24 * scaleX),
            height: min(CGFloat(screenshot.height), 24 * scaleY)
        ).integral
        pinButton.usesDarkSymbol = OverlayPinAppearance.usesDarkSymbol(
            backgroundLuminance: screenshot.averageLuminance(in: sampleRect)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if let screenshot {
            NSImage(cgImage: screenshot, size: bounds.size).draw(in: bounds)
        }

        drawTranslations()
    }

    private func drawTranslations() {
        guard displayMode == .translation, !translatedBlocks.isEmpty else { return }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byCharWrapping

        let sortedBlocks = translatedBlocks.sorted {
            let lhs = $0.original.boundingBox.scaledDown(by: displayScale)
            let rhs = $1.original.boundingBox.scaledDown(by: displayScale)
            if abs(lhs.minY - rhs.minY) > 6 {
                return lhs.minY < rhs.minY
            }
            return lhs.minX < rhs.minX
        }
        let typography = stableTypography(for: sortedBlocks)
        let sourceRects = sortedBlocks.map { $0.original.boundingBox.scaledDown(by: displayScale) }
        let coverRects = OverlayLayoutPlanner.plan(
            sourceRects: sourceRects,
            in: bounds,
            minimumSize: OverlayGeometry.minimumReadableSize
        )

        for (index, block) in sortedBlocks.enumerated() {
            let rect = sourceRects[index]
            let layout = textLayout(
                for: block.translatedText,
                baseRect: rect,
                coverRect: coverRects[index],
                sourceStyle: block.original.visualStyle,
                typography: typography
            )

            NSColor.white.withAlphaComponent(0.97).setFill()
            NSBezierPath(roundedRect: layout.coverRect, xRadius: 3, yRadius: 3).fill()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: layout.font,
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraphStyle
            ]
            (block.translatedText as NSString).draw(
                in: layout.textRect,
                withAttributes: attrs
            )
        }
    }

    private func textLayout(
        for text: String,
        baseRect: CGRect,
        coverRect: CGRect,
        sourceStyle: TextBlockVisualStyle,
        typography: StableTypography
    ) -> TextRenderLayout {
        let display = isDisplayBlock(baseRect)
        let sourceFontSize = sourceStyle.estimatedFontSize > 0
            ? sourceStyle.estimatedFontSize / max(displayScale, 1)
            : baseRect.height * 0.72
        let targetSize = display
            ? min(max(16, typography.displayFontSize), 28)
            : min(max(12, min(sourceFontSize, typography.bodyFontSize)), 21)
        let inset = textInset(for: coverRect)
        let verticalInset = min(max(1, inset * 0.7), max(0, coverRect.height * 0.22))
        let horizontalInset = min(inset, max(0, coverRect.width * 0.14))
        let textRect = coverRect.insetBy(dx: horizontalInset, dy: verticalInset).integral
        let font = fontThatFits(text: text, in: textRect, targetSize: targetSize, display: display)
        return TextRenderLayout(coverRect: coverRect, textRect: textRect, font: font)
    }

    private func stableTypography(for blocks: [TranslatedBlock]) -> StableTypography {
        let bodySizes = blocks
            .filter { !isDisplayBlock($0.original.boundingBox.scaledDown(by: displayScale)) }
            .map { estimatedSourceFontSize(for: $0.original) }
            .sorted()
        let displaySizes = blocks
            .filter { isDisplayBlock($0.original.boundingBox.scaledDown(by: displayScale)) }
            .map { estimatedSourceFontSize(for: $0.original) }
            .sorted()
        let body = bodySizes.isEmpty ? 16 : bodySizes[bodySizes.count / 2]
        let display = displaySizes.isEmpty ? max(body, 20) : displaySizes[displaySizes.count / 2]
        return StableTypography(
            bodyFontSize: min(max(13, body), 20),
            displayFontSize: min(max(18, display), 26)
        )
    }

    private func estimatedSourceFontSize(for block: TextBlock) -> CGFloat {
        if block.visualStyle.estimatedFontSize > 0 {
            return block.visualStyle.estimatedFontSize / max(displayScale, 1)
        }
        return block.boundingBox.scaledDown(by: displayScale).height * 0.72
    }

    private func fontThatFits(text: String, in textRect: CGRect, targetSize: CGFloat, display: Bool) -> NSFont {
        let width = max(1, textRect.width)
        let height = max(1, textRect.height)
        let minimumSize: CGFloat = display ? 12 : 10
        var low = minimumSize
        var high = max(targetSize, low)
        var best = minimumSize

        let targetFont = preferredFont(size: targetSize, display: display)
        if text.boundingSize(font: targetFont, width: width).height <= height + 0.5 {
            return targetFont
        }

        while high - low > 0.15 {
            let size = (low + high) / 2
            let font = preferredFont(size: size, display: display)
            let required = text.boundingSize(font: font, width: width)

            if required.height <= height + 0.5 {
                best = size
                low = size
            } else {
                high = size
            }
        }

        return preferredFont(size: best, display: display)
    }

    private func textInset(for rect: CGRect) -> CGFloat {
        let cap: CGFloat = rect.height > 70 ? 8 : 4
        return max(1, min(cap, min(rect.width, rect.height) * 0.12))
    }

    private func isDisplayBlock(_ rect: CGRect) -> Bool {
        rect.height >= 56 || (rect.width > bounds.width * 0.28 && rect.height >= 34)
    }

    private func preferredFont(size: CGFloat, display: Bool) -> NSFont {
        if display {
            return NSFont(name: "Songti SC", size: size)
                ?? NSFont(name: "STSong", size: size)
                ?? .systemFont(ofSize: size, weight: .semibold)
        }
        return .systemFont(ofSize: size, weight: .regular)
    }

    func renderToImage() -> CGImage? {
        displayIfNeeded()
        guard let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        cacheDisplay(in: bounds, to: bitmap)
        return bitmap.cgImage
    }
}

private final class OverlayPinButton: NSControl {
    var onClick: (() -> Void)?
    var usesDarkSymbol = false { didSet { needsDisplay = true } }
    var isPinned = false {
        didSet {
            toolTip = isPinned ? "解除钉住" : "钉住浮框"
            needsDisplay = true
        }
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let image = NSImage(systemSymbolName: isPinned ? "pin.fill" : "pin", accessibilityDescription: isPinned ? "解除钉住" : "钉住")
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(.init(paletteColors: [usesDarkSymbol ? .black : .white]))
        guard let configuredImage = image?.withSymbolConfiguration(symbolConfiguration) else { return }
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: bounds.midX, yBy: bounds.midY)
        transform.rotate(byDegrees: OverlayPinAppearance.symbolRotationDegrees(isPinned: isPinned))
        transform.translateX(by: -bounds.midX, yBy: -bounds.midY)
        transform.concat()
        configuredImage.draw(in: bounds.insetBy(dx: 5, dy: 5))
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
}

private extension CGImage {
    func averageLuminance(in rect: CGRect) -> Double {
        let clipped = rect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1,
              let crop = cropping(to: clipped) else { return 0 }
        let size = 8
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: size,
                    height: size,
                    bitsPerComponent: 8,
                    bytesPerRow: size * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.interpolationQuality = .low
            context.draw(crop, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard rendered else { return 0 }
        var total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            total += 0.2126 * red + 0.7152 * green + 0.0722 * blue
        }
        return total / Double(size * size)
    }
}

fileprivate enum OverlayDisplayMode {
    case original
    case translation
}

private struct TextRenderLayout {
    let coverRect: CGRect
    let textRect: CGRect
    let font: NSFont
}

private struct StableTypography {
    let bodyFontSize: CGFloat
    let displayFontSize: CGFloat
}

private extension String {
    var shortStatusText: String {
        if contains("识别") { return "正在识别" }
        if contains("翻译") { return "正在翻译" }
        return self
    }
}

private extension String {
    func boundingSize(font: NSFont, width: CGFloat) -> CGSize {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byCharWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
        return (self as NSString).boundingRect(
            with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        ).size
    }
}

private extension CGRect {
    func scaledDown(by scale: CGFloat) -> CGRect {
        let value = max(scale, 1.0)
        return CGRect(
            x: origin.x / value,
            y: origin.y / value,
            width: width / value,
            height: height / value
        )
    }
}
