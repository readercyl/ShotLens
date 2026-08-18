import AppKit
import CoreGraphics

enum OverlayGeometry {
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

    static func displayRect(
        forPixelRect pixelRect: CGRect,
        screenshotPixelSize: CGSize,
        displayBounds: CGRect
    ) -> CGRect {
        guard screenshotPixelSize.width > 0,
              screenshotPixelSize.height > 0,
              displayBounds.width > 0,
              displayBounds.height > 0 else {
            return .zero
        }
        return CGRect(
            x: displayBounds.minX + pixelRect.minX / screenshotPixelSize.width * displayBounds.width,
            y: displayBounds.minY + pixelRect.minY / screenshotPixelSize.height * displayBounds.height,
            width: pixelRect.width / screenshotPixelSize.width * displayBounds.width,
            height: pixelRect.height / screenshotPixelSize.height * displayBounds.height
        )
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
    private var pinWindow: OverlayPinWindow?
    private var backdropWindows: [OverlayBackdropWindow] = []
    private var contentView: OverlayContentView?
    private var outsideClickMonitor: Any?
    private var didDismiss = false
    private var isShowingTranslation = true
    private var isPinned = false
    private var isRetranslating = false
    private var controlPhase: OverlayControlPhase = .processing
    private var translationStatusMessage = "翻译完成"

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
        window.contentView = contentView

        let statusWindow = OverlayStatusWindow(anchorRect: windowRect)
        statusWindow.setMessage("正在识别")

        let pinWindow = OverlayPinWindow(anchorRect: windowRect)
        pinWindow.setScreenshot(croppedScreenshot)
        pinWindow.onTogglePin = { [weak self] in self?.togglePinned() }

        self.resultWindow = window
        self.statusWindow = statusWindow
        self.pinWindow = pinWindow
        self.contentView = contentView

        window.addChildWindow(statusWindow, ordered: .above)
        window.addChildWindow(pinWindow, ordered: .above)

        backdropWindows.forEach { $0.orderFrontRegardless() }
        window.orderFrontRegardless()
        statusWindow.orderFrontRegardless()
        pinWindow.orderFrontRegardless()
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
    func setTranslatedBlocks(_ blocks: [TranslatedBlock], isPartial: Bool = false) {
        controlPhase = .success
        isRetranslating = false
        isShowingTranslation = true
        translationStatusMessage = isPartial ? "部分完成" : "翻译完成"
        contentView?.setTranslatedBlocks(blocks)
        contentView?.setDisplayMode(.translation)
        setToggleStatus(message: translationStatusMessage)
    }

    @MainActor
    func setMessage(_ message: String) {
        let isFailure = message.contains("失败")
            || message.contains("未识别")
            || message.contains("未配置")
        controlPhase = isFailure ? .failure : .processing
        isRetranslating = false
        isShowingTranslation = true
        contentView?.setTranslatedBlocks([])
        contentView?.setDisplayMode(.translation)
        if isFailure {
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
                if self.pinWindow?.frame.contains(mouseLocation) == true {
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
        pinWindow?.setPinned(isPinned)
        syncControlWindows()
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
        if let resultWindow {
            if let statusWindow { resultWindow.removeChildWindow(statusWindow) }
            if let saveWindow { resultWindow.removeChildWindow(saveWindow) }
            if let pinWindow { resultWindow.removeChildWindow(pinWindow) }
        }
        resultWindow = nil
        statusWindow?.close()
        statusWindow = nil
        saveWindow?.close()
        saveWindow = nil
        pinWindow?.close()
        pinWindow = nil
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
        syncControlWindows()
    }

    private func syncControlWindows() {
        guard let resultWindow else { return }
        statusWindow?.syncAnchorRect(resultWindow.frame)
        if let statusWindow {
            saveWindow?.syncStatusFrame(statusWindow.frame)
        }
        pinWindow?.syncAnchorRect(resultWindow.frame)
    }

    @MainActor
    private func toggleOriginalAndTranslation() {
        isShowingTranslation.toggle()
        if isShowingTranslation {
            contentView?.setDisplayMode(.translation)
            setToggleStatus(message: translationStatusMessage)
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
        ClipboardManager().copyImageToClipboard(image: image)
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
            onToggle: { [weak self] in self?.toggleOriginalAndTranslation() }
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
        pinWindow?.orderFrontRegardless()
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
        resultWindow?.addChildWindow(window, ordered: .above)
        saveWindow = window
        window.orderFrontRegardless()
    }
}

private final class OverlayToolbarWindow: NSPanel {
    var onToggleMode: (() -> Void)? {
        didSet { toolbarView.onToggleMode = onToggleMode }
    }
    var onCopyText: (() -> Void)? {
        didSet { toolbarView.onCopyText = onCopyText }
    }
    var onCopyImage: (() -> Void)? {
        didSet { toolbarView.onCopyImage = onCopyImage }
    }
    var onRetranslate: (() -> Void)? {
        didSet { toolbarView.onRetranslate = onRetranslate }
    }
    var onRetry: (() -> Void)? {
        didSet { toolbarView.onRetry = onRetry }
    }

    private var anchorRect: CGRect
    private let toolbarView = OverlayToolbarView(frame: CGRect(x: 0, y: 0, width: 160, height: 34))

    init(anchorRect: CGRect) {
        self.anchorRect = anchorRect
        super.init(
            contentRect: Self.frame(for: anchorRect, size: toolbarView.preferredSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = OverlayWindow.controlLevel
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        collectionBehavior = OverlayWindow.fullscreenOverlayBehavior
        contentView = toolbarView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setProcessing(_ message: String) {
        toolbarView.setProcessing(message)
        updateFrame()
    }

    func setFailure(message: String) {
        toolbarView.setFailure(message: message)
        updateFrame()
        orderFrontRegardless()
    }

    func setSuccess(showingTranslation: Bool, message: String) {
        toolbarView.setSuccess(showingTranslation: showingTranslation, message: message)
        updateFrame()
        orderFrontRegardless()
    }

    func showFeedback(_ message: String) {
        toolbarView.showFeedback(message)
    }

    private func updateFrame() {
        let size = toolbarView.preferredSize
        toolbarView.frame = CGRect(origin: .zero, size: size)
        setFrame(Self.frame(for: anchorRect, size: size), display: true)
    }

    private static func frame(for anchorRect: CGRect, size: CGSize) -> CGRect {
        let gap: CGFloat = 8
        let screenFrame = NSScreen.screens.first { $0.frame.intersects(anchorRect) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? anchorRect
        let safeFrame = screenFrame.insetBy(dx: 8, dy: 8)
        let candidates = [
            CGRect(x: anchorRect.midX - size.width / 2, y: anchorRect.minY - gap - size.height, width: size.width, height: size.height),
            CGRect(x: anchorRect.midX - size.width / 2, y: anchorRect.maxY + gap, width: size.width, height: size.height),
            CGRect(x: anchorRect.maxX + gap, y: anchorRect.maxY - size.height, width: size.width, height: size.height),
            CGRect(x: anchorRect.minX - gap - size.width, y: anchorRect.maxY - size.height, width: size.width, height: size.height)
        ]
        return candidates.first(where: { safeFrame.contains($0) }) ?? CGRect(
            x: min(max(anchorRect.midX - size.width / 2, safeFrame.minX), safeFrame.maxX - size.width),
            y: min(max(anchorRect.minY - gap - size.height, safeFrame.minY), safeFrame.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }
}

private final class OverlayToolbarStatusLabel: NSView {
    var text = "" { didSet { needsDisplay = true } }
    var font = NSFont.systemFont(ofSize: 12, weight: .medium) { didSet { needsDisplay = true } }
    var textColor: NSColor = .labelColor { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let point = CGPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2
        )
        (text as NSString).draw(at: point, withAttributes: attributes)
    }
}

private final class OverlayToolbarView: NSView {
    var onToggleMode: (() -> Void)? {
        didSet { modeButton.onClick = onToggleMode }
    }
    var onCopyText: (() -> Void)? {
        didSet { copyButton.onClick = onCopyText }
    }
    var onCopyImage: (() -> Void)? {
        didSet { copyImageButton.onClick = onCopyImage }
    }
    var onRetranslate: (() -> Void)? {
        didSet { retranslateButton.onClick = { [weak self] in self?.performRetranslateOrRetry() } }
    }
    var onRetry: (() -> Void)?

    private enum State {
        case processing(String)
        case failure(String)
        case success(showingTranslation: Bool, message: String)
    }

    private var state: State = .processing("正在识别")
    private let modeButton = OverlayToolbarIconButton(symbolName: "eye", label: "显示原文")
    private let copyButton = OverlayToolbarIconButton(symbolName: "doc.on.doc", label: "复制译文")
    private let retranslateButton = OverlayToolbarIconButton(symbolName: "arrow.clockwise", label: "重新翻译")
    private let copyImageButton = OverlayToolbarIconButton(symbolName: "photo.on.rectangle", label: "复制截图")
    private let messageLabel = OverlayToolbarStatusLabel()
    private var feedbackReset: DispatchWorkItem?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    var preferredSize: CGSize {
        CGSize(width: 222, height: 34)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        modeButton.onClick = onToggleMode
        copyButton.onClick = onCopyText
        retranslateButton.onClick = { [weak self] in self?.performRetranslateOrRetry() }
        copyImageButton.onClick = onCopyImage
        addSubview(modeButton)
        addSubview(copyButton)
        addSubview(retranslateButton)
        addSubview(copyImageButton)
        addSubview(messageLabel)
        updateStateVisibility()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setProcessing(_ message: String) {
        state = .processing(message)
        updateStateVisibility()
    }

    func setFailure(message: String) {
        state = .failure(message)
        updateStateVisibility()
    }

    func setSuccess(showingTranslation: Bool, message: String) {
        feedbackReset?.cancel()
        state = .success(showingTranslation: showingTranslation, message: message)
        updateStateVisibility()
    }

    func showFeedback(_ message: String) {
        guard case .success(let showingTranslation, _) = state else { return }
        feedbackReset?.cancel()
        state = .success(showingTranslation: showingTranslation, message: message)
        updateStateVisibility()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  case .success(let currentMode, _) = self.state else { return }
            self.state = .success(showingTranslation: currentMode, message: "已翻译")
            self.updateStateVisibility()
        }
        feedbackReset = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: workItem)
    }

    override func layout() {
        super.layout()
        switch state {
        case .success(let showingTranslation, _):
            modeButton.symbolName = showingTranslation ? "eye" : "character"
            modeButton.label = showingTranslation ? "显示原文" : "显示翻译"
        case .processing, .failure:
            break
        }
        messageLabel.frame = CGRect(x: 8, y: 0, width: 66, height: 34)
        modeButton.frame = CGRect(x: 82, y: 3, width: 28, height: 28)
        copyButton.frame = CGRect(x: 116, y: 3, width: 28, height: 28)
        retranslateButton.frame = CGRect(x: 150, y: 3, width: 28, height: 28)
        copyImageButton.frame = CGRect(x: 184, y: 3, width: 28, height: 28)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
        NSColor.separatorColor.withAlphaComponent(0.8).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        border.lineWidth = 1
        border.stroke()
        NSColor.separatorColor.withAlphaComponent(0.7).setStroke()
        let separator = NSBezierPath()
        separator.move(to: CGPoint(x: 77.5, y: 7))
        separator.line(to: CGPoint(x: 77.5, y: bounds.maxY - 7))
        separator.lineWidth = 1
        separator.stroke()
    }

    private func updateStateVisibility() {
        modeButton.isHidden = false
        copyButton.isHidden = false
        retranslateButton.isHidden = false
        copyImageButton.isHidden = false
        messageLabel.isHidden = false

        switch state {
        case .success(_, let message):
            messageLabel.text = message == "翻译完成" ? "已翻译" : message
            modeButton.isEnabled = true
            copyButton.isEnabled = true
            retranslateButton.isEnabled = true
            copyImageButton.isEnabled = true
            retranslateButton.label = "重新翻译"
        case .processing(let message):
            messageLabel.text = message
            modeButton.isEnabled = false
            copyButton.isEnabled = false
            retranslateButton.isEnabled = false
            copyImageButton.isEnabled = false
            retranslateButton.label = "重新翻译"
        case .failure(let message):
            messageLabel.text = message
            modeButton.isEnabled = false
            copyButton.isEnabled = false
            retranslateButton.isEnabled = true
            copyImageButton.isEnabled = false
            retranslateButton.label = "重试"
        }
        needsLayout = true
        needsDisplay = true
    }

    private func performRetranslateOrRetry() {
        switch state {
        case .failure:
            onRetry?()
        case .success:
            onRetranslate?()
        case .processing:
            break
        }
    }
}

private final class OverlayToolbarIconButton: NSControl {
    var symbolName: String { didSet { needsDisplay = true } }
    var label: String {
        didSet {
            toolTip = label
            setAccessibilityLabel(label)
            needsDisplay = true
        }
    }
    var onClick: (() -> Void)?
    private var isHovered = false { didSet { needsDisplay = true } }
    private var isPressed = false { didSet { needsDisplay = true } }

    init(symbolName: String, label: String) {
        self.symbolName = symbolName
        self.label = label
        super.init(frame: .zero)
        toolTip = label
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            self.isPressed = false
            self.onClick?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isPressed || (isHovered && isEnabled) {
            NSColor.labelColor.withAlphaComponent(isPressed ? 0.18 : 0.1).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)?.withSymbolConfiguration(
            .init(pointSize: 14, weight: .medium)
        ) else { return }
        let size = image.size
        image.draw(
            in: CGRect(
            x: floor((bounds.width - size.width) / 2),
            y: floor((bounds.height - size.height) / 2),
            width: size.width,
            height: size.height
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: isEnabled ? 1 : 0.32,
            respectFlipped: true,
            hints: nil
        )
    }
}

private final class OverlayToolbarTextButton: NSControl {
    let title: String
    var onClick: (() -> Void)?

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
        toolTip = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
    }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

private final class OverlayToolbarMenuTarget: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func invoke(_ sender: Any?) { action() }
}

private final class OverlayPinWindow: NSPanel {
    var onTogglePin: (() -> Void)?

    private var anchorRect: CGRect
    private let pinButton = OverlayPinButton(frame: CGRect(x: 0, y: 0, width: 28, height: 28))

    init(anchorRect: CGRect) {
        self.anchorRect = anchorRect
        super.init(
            contentRect: Self.frame(for: anchorRect),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = OverlayWindow.controlLevel
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        collectionBehavior = OverlayWindow.fullscreenOverlayBehavior
        pinButton.toolTip = "钉住浮框"
        pinButton.setAccessibilityRole(.button)
        pinButton.setAccessibilityLabel("钉住浮框")
        pinButton.onClick = { [weak self] in self?.onTogglePin?() }
        contentView = pinButton
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setPinned(_ pinned: Bool) {
        pinButton.isPinned = pinned
    }

    func setScreenshot(_ screenshot: CGImage) {
        let sampleRect = CGRect(
            x: max(0, CGFloat(screenshot.width) - 36),
            y: 4,
            width: min(36, CGFloat(screenshot.width)),
            height: min(36, CGFloat(screenshot.height))
        )
        pinButton.symbolColor = OverlayPinAppearance.usesDarkSymbol(
            backgroundLuminance: screenshot.averageLuminance(in: sampleRect)
        ) ? .black : .white
    }

    func syncAnchorRect(_ rect: CGRect) {
        anchorRect = rect
        let target = Self.frame(for: rect)
        if abs(target.minX - frame.minX) > 0.5 || abs(target.minY - frame.minY) > 0.5 {
            setFrameOrigin(target.origin)
        }
    }

    private static func frame(for anchorRect: CGRect) -> CGRect {
        let size = CGSize(width: 28, height: 28)
        let gap: CGFloat = 8
        let screenFrame = NSScreen.screens.first { $0.frame.intersects(anchorRect) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? anchorRect
        let candidates = [
            CGRect(x: anchorRect.maxX + gap, y: anchorRect.maxY - size.height, width: size.width, height: size.height),
            CGRect(x: anchorRect.minX - gap - size.width, y: anchorRect.maxY - size.height, width: size.width, height: size.height),
            CGRect(x: anchorRect.maxX - size.width, y: anchorRect.maxY + gap, width: size.width, height: size.height),
            CGRect(x: anchorRect.maxX - size.width, y: anchorRect.minY - gap - size.height, width: size.width, height: size.height)
        ]
        let safeFrame = screenFrame.insetBy(dx: 8, dy: 8)
        return candidates.first(where: { safeFrame.contains($0) }) ?? CGRect(
            x: min(max(anchorRect.maxX + gap, safeFrame.minX), safeFrame.maxX - size.width),
            y: min(max(anchorRect.maxY - size.height, safeFrame.minY), safeFrame.maxY - size.height),
            width: size.width,
            height: size.height
        )
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

    func syncAnchorRect(_ rect: CGRect) {
        anchorRect = rect
        let target = statusFrame(size: frame.size)
        if abs(target.minX - frame.minX) > 0.5 || abs(target.minY - frame.minY) > 0.5 {
            setFrameOrigin(target.origin)
        }
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

    func syncStatusFrame(_ statusFrame: CGRect) {
        let target = Self.frame(for: statusFrame)
        if abs(target.minX - frame.minX) > 0.5 || abs(target.minY - frame.minY) > 0.5 {
            setFrameOrigin(target.origin)
        }
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
    var screenshot: CGImage? {
        didSet { needsDisplay = true }
    }
    var displayScale: CGFloat = 1.0
    var translatedBlocks: [TranslatedBlock] = []
    private var displayMode: OverlayDisplayMode = .translation

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

    fileprivate func setDisplayMode(_ mode: OverlayDisplayMode) {
        displayMode = mode
        needsDisplay = true
    }

    private func setupControls() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func layout() {
        super.layout()
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

        guard let screenshot else { return }
        let screenshotSize = CGSize(width: screenshot.width, height: screenshot.height)
        let sortedBlocks = translatedBlocks.sorted {
            let lhs = $0.original.boundingBox
            let rhs = $1.original.boundingBox
            if abs(lhs.minY - rhs.minY) > 6 {
                return lhs.minY < rhs.minY
            }
            return lhs.minX < rhs.minX
        }
        let sourceRects = sortedBlocks.map {
            OverlayGeometry.displayRect(
                forPixelRect: $0.original.boundingBox,
                screenshotPixelSize: screenshotSize,
                displayBounds: bounds
            ).intersection(bounds)
        }

        if shouldReflow(sortedBlocks: sortedBlocks, sourceRects: sourceRects) {
            drawReflowedTranslations(
                sortedBlocks: sortedBlocks,
                sourceRects: sourceRects,
                screenshotSize: screenshotSize,
                paragraphStyle: paragraphStyle
            )
            return
        }

        for (index, block) in sortedBlocks.enumerated() {
            let rect = sourceRects[index]
            guard rect.width > 0, rect.height > 0 else { continue }
            let layout = textLayout(
                for: block.translatedText,
                baseRect: rect,
                sourceStyle: block.original.visualStyle
            )

            restoreBackground(for: block, screenshotSize: screenshotSize, displayRect: rect)

            let backgroundColor = sampledBackgroundColor(forPixelRect: block.original.boundingBox)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: layout.font,
                .foregroundColor: resolvedTextColor(
                    sourceStyle: block.original.visualStyle,
                    backgroundColor: backgroundColor
                ),
                .paragraphStyle: paragraphStyle
            ]
            (block.translatedText as NSString).draw(
                in: layout.textRect,
                withAttributes: attrs
            )
        }
    }

    private func shouldReflow(
        sortedBlocks: [TranslatedBlock],
        sourceRects: [CGRect]
    ) -> Bool {
        guard sortedBlocks.count >= 2,
              sourceRects.count == sortedBlocks.count,
              sourceRects.allSatisfy({ $0.width > 0 && $0.height > 0 }) else {
            return false
        }
        let first = sourceRects[0]
        let lineHeight = max(1, first.height)
        let sameFlow = sourceRects.dropFirst().allSatisfy {
            abs($0.minX - first.minX) <= max(24, lineHeight * 1.5)
        }
        guard sameFlow else { return false }
        return sortedBlocks.enumerated().contains { index, block in
            textLayout(
                for: block.translatedText,
                baseRect: sourceRects[index],
                sourceStyle: block.original.visualStyle
            ).font.pointSize < 10.5
        }
    }

    private func drawReflowedTranslations(
        sortedBlocks: [TranslatedBlock],
        sourceRects: [CGRect],
        screenshotSize: CGSize,
        paragraphStyle: NSParagraphStyle
    ) {
        guard let first = sortedBlocks.first else { return }
        for (index, block) in sortedBlocks.enumerated() {
            restoreBackground(for: block, screenshotSize: screenshotSize, displayRect: sourceRects[index])
        }

        let flowRect = sourceRects.dropFirst().reduce(sourceRects[0]) { $0.union($1) }
        let text = sortedBlocks.map(\.translatedText).joined(separator: "\n")
        let pixelScaleY = screenshot.map { CGFloat($0.height) / max(bounds.height, 1) } ?? max(displayScale, 1)
        let sourceSizes = sortedBlocks.map { block in
            block.original.visualStyle.estimatedFontSize > 0
                ? block.original.visualStyle.estimatedFontSize / max(pixelScaleY, 1)
                : 14
        }
        let targetSize = min(20, max(11, sourceSizes.reduce(0, +) / CGFloat(max(1, sourceSizes.count))))
        let font = fontThatFits(text: text, in: flowRect, targetSize: targetSize, minimumSize: 11)
        let backgroundColor = sampledBackgroundColor(forPixelRect: first.original.boundingBox)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: resolvedTextColor(sourceStyle: first.original.visualStyle, backgroundColor: backgroundColor),
            .paragraphStyle: paragraphStyle
        ]
        (text as NSString).draw(in: flowRect, withAttributes: attrs)
    }

    private func restoreBackground(
        for block: TranslatedBlock,
        screenshotSize: CGSize,
        displayRect: CGRect
    ) {
        guard let screenshot else { return }
        if let restored = OverlayTextBackgroundRestorer.restoredPatch(
            from: screenshot,
            pixelRect: block.original.boundingBox,
            sourceStyle: block.original.visualStyle
        ) {
            let restoredPixelRect = OverlayTextBackgroundRestorer.restorationPixelRect(
                for: block.original.boundingBox,
                imageSize: screenshotSize
            )
            let restoredDisplayRect = OverlayGeometry.displayRect(
                forPixelRect: restoredPixelRect,
                screenshotPixelSize: screenshotSize,
                displayBounds: bounds
            )
            NSImage(cgImage: restored, size: restoredDisplayRect.size).draw(in: restoredDisplayRect)
        } else {
            drawFallbackBackground(in: displayRect, forPixelRect: block.original.boundingBox)
        }
    }

    private func sampledBackgroundColor(forPixelRect pixelRect: CGRect) -> NSColor {
        guard let screenshot else { return .windowBackgroundColor }
        return screenshot.averageColor(in: pixelRect) ?? .windowBackgroundColor
    }

    private func drawFallbackBackground(in displayRect: CGRect, forPixelRect pixelRect: CGRect) {
        sampledBackgroundColor(forPixelRect: pixelRect).setFill()
        NSBezierPath(rect: displayRect).fill()
    }

    private func resolvedTextColor(
        sourceStyle: TextBlockVisualStyle,
        backgroundColor: NSColor
    ) -> NSColor {
        let backgroundLuminance = backgroundColor.relativeLuminance
        if sourceStyle.foregroundLuminance >= 0 {
            let sourceColor = NSColor(
                calibratedRed: sourceStyle.foregroundRed,
                green: sourceStyle.foregroundGreen,
                blue: sourceStyle.foregroundBlue,
                alpha: 1
            )
            if sourceColor.contrastRatio(againstLuminance: backgroundLuminance) >= 3.2 {
                return sourceColor
            }
        }
        return backgroundLuminance > 0.48 ? .black : .white
    }

    private func textLayout(
        for text: String,
        baseRect: CGRect,
        sourceStyle: TextBlockVisualStyle
    ) -> TextRenderLayout {
        let pixelScaleY = screenshot.map { CGFloat($0.height) / max(bounds.height, 1) }
            ?? max(displayScale, 1)
        let sourceFontSize = sourceStyle.estimatedFontSize > 0
            ? sourceStyle.estimatedFontSize / max(pixelScaleY, 1)
            : baseRect.height * 0.72
        let targetSize = min(max(8, sourceFontSize), 22)
        let font = fontThatFits(text: text, in: baseRect, targetSize: targetSize)
        let renderedHeight = min(baseRect.height, text.boundingSize(font: font, width: baseRect.width).height)
        let textRect = CGRect(
            x: baseRect.minX,
            y: baseRect.minY + max(0, (baseRect.height - renderedHeight) / 2),
            width: baseRect.width,
            height: renderedHeight
        )
        return TextRenderLayout(textRect: textRect, font: font)
    }

    private func fontThatFits(text: String, in textRect: CGRect, targetSize: CGFloat, minimumSize: CGFloat = 8) -> NSFont {
        let width = max(1, textRect.width)
        let height = max(1, textRect.height)
        var low = minimumSize
        var high = max(targetSize, low)
        var best = minimumSize

        let targetFont = preferredFont(size: targetSize)
        if text.boundingSize(font: targetFont, width: width).height <= height + 0.5 {
            return targetFont
        }

        while high - low > 0.15 {
            let size = (low + high) / 2
            let font = preferredFont(size: size)
            let required = text.boundingSize(font: font, width: width)

            if required.height <= height + 0.5 {
                best = size
                low = size
            } else {
                high = size
            }
        }

        return preferredFont(size: best)
    }

    private func preferredFont(size: CGFloat) -> NSFont {
        .systemFont(ofSize: size, weight: .regular)
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
    var symbolColor: NSColor = .labelColor { didSet { needsDisplay = true } }
    var usesDarkSymbol = false { didSet { needsDisplay = true } }
    var isPinned = false {
        didSet {
            toolTip = isPinned ? "解除钉住" : "钉住浮框"
            setAccessibilityLabel(toolTip)
            needsDisplay = true
        }
    }
    private var isHovered = false { didSet { needsDisplay = true } }
    private var isPressed = false { didSet { needsDisplay = true } }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func draw(_ dirtyRect: NSRect) {
        let image = NSImage(systemSymbolName: isPinned ? "pin.fill" : "pin", accessibilityDescription: isPinned ? "解除钉住" : "钉住")
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
            .applying(.init(paletteColors: [isPressed || isHovered ? NSColor.controlAccentColor : symbolColor]))
        guard let configuredImage = image?.withSymbolConfiguration(symbolConfiguration) else { return }
        let imageSize = configuredImage.size
        let imageRect = CGRect(
            x: floor((bounds.width - imageSize.width) / 2),
            y: floor((bounds.height - imageSize.height) / 2),
            width: imageSize.width,
            height: imageSize.height
        )
        configuredImage.draw(
            in: imageRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            self.isPressed = false
            self.onClick?()
        }
    }
}

enum OverlayTextBackgroundRestorer {
    static func restorationPixelRect(for pixelRect: CGRect, imageSize: CGSize) -> CGRect {
        pixelRect
            .insetBy(dx: -1, dy: -1)
            .integral
            .intersection(CGRect(origin: .zero, size: imageSize))
    }

    static func restoredPatch(
        from image: CGImage,
        pixelRect: CGRect,
        sourceStyle _: TextBlockVisualStyle
    ) -> CGImage? {
        let imageSize = CGSize(width: image.width, height: image.height)
        let targetRect = restorationPixelRect(for: pixelRect, imageSize: imageSize)
        guard !targetRect.isNull, targetRect.width >= 1, targetRect.height >= 1 else { return nil }

        let padding = max(2, min(12, Int((targetRect.height * 0.24).rounded(.up))))
        let sampleRect = targetRect
            .insetBy(dx: -CGFloat(padding), dy: -CGFloat(padding))
            .integral
            .intersection(CGRect(origin: .zero, size: imageSize))
        guard let crop = image.cropping(to: sampleRect) else { return nil }

        let sampleWidth = crop.width
        let sampleHeight = crop.height
        guard sampleWidth > 0, sampleHeight > 0,
              let samplePixels = rgbaPixels(from: crop) else { return nil }

        let targetWidth = Int(targetRect.width)
        let targetHeight = Int(targetRect.height)
        let offsetX = Int(targetRect.minX - sampleRect.minX)
        let offsetY = Int(targetRect.minY - sampleRect.minY)
        guard targetWidth > 0, targetHeight > 0,
              offsetX >= 0, offsetY >= 0,
              offsetX + targetWidth <= sampleWidth,
              offsetY + targetHeight <= sampleHeight else { return nil }

        var output = [UInt8](repeating: 0, count: targetWidth * targetHeight * 4)
        let topSampleY = max(0, offsetY - 1)
        let bottomSampleY = min(sampleHeight - 1, offsetY + targetHeight)
        let leftSampleX = max(0, offsetX - 1)
        let rightSampleX = min(sampleWidth - 1, offsetX + targetWidth)
        let cornerIndexes = [
            0,
            (sampleWidth - 1) * 4,
            ((sampleHeight - 1) * sampleWidth) * 4,
            ((sampleHeight * sampleWidth) - 1) * 4
        ]
        let reference = averageColor(at: cornerIndexes, pixels: samplePixels)

        for y in 0..<targetHeight {
            let verticalAmount = targetHeight == 1 ? 0.5 : Double(y) / Double(targetHeight - 1)
            for x in 0..<targetWidth {
                let sampleX = offsetX + x
                let topIndex = (topSampleY * sampleWidth + sampleX) * 4
                let bottomIndex = (bottomSampleY * sampleWidth + sampleX) * 4
                let vertical = interpolatedColor(
                    pixels: samplePixels,
                    topIndex: topIndex,
                    bottomIndex: bottomIndex,
                    amount: verticalAmount
                )
                let sampleY = offsetY + y
                let leftIndex = (sampleY * sampleWidth + leftSampleX) * 4
                let rightIndex = (sampleY * sampleWidth + rightSampleX) * 4
                let horizontalAmount = targetWidth == 1 ? 0.5 : Double(x) / Double(targetWidth - 1)
                let horizontal = interpolatedColor(
                    pixels: samplePixels,
                    topIndex: leftIndex,
                    bottomIndex: rightIndex,
                    amount: horizontalAmount
                )
                let verticalBoundaryDistance = colorDistance(
                    color(at: topIndex, pixels: samplePixels),
                    color(at: bottomIndex, pixels: samplePixels)
                )
                let horizontalBoundaryDistance = colorDistance(
                    color(at: leftIndex, pixels: samplePixels),
                    color(at: rightIndex, pixels: samplePixels)
                )
                let verticalScore = verticalBoundaryDistance + colorDistance(vertical, reference) * 0.35
                let horizontalScore = horizontalBoundaryDistance + colorDistance(horizontal, reference) * 0.35
                let predicted = verticalScore <= horizontalScore ? vertical : horizontal
                let outputIndex = (y * targetWidth + x) * 4
                output[outputIndex] = UInt8((predicted.red * 255).rounded().clamped(to: 0...255))
                output[outputIndex + 1] = UInt8((predicted.green * 255).rounded().clamped(to: 0...255))
                output[outputIndex + 2] = UInt8((predicted.blue * 255).rounded().clamped(to: 0...255))
                output[outputIndex + 3] = 255
            }
        }
        return makeImage(width: targetWidth, height: targetHeight, pixels: output)
    }

    private static func rgbaPixels(from image: CGImage) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: base,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: image.width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return rendered ? pixels : nil
    }

    private static func makeImage(width: Int, height: Int, pixels: [UInt8]) -> CGImage? {
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private static func interpolatedColor(
        pixels: [UInt8],
        topIndex: Int,
        bottomIndex: Int,
        amount: Double
    ) -> (red: Double, green: Double, blue: Double) {
        let inverse = 1 - amount
        return (
            red: (Double(pixels[topIndex]) * inverse + Double(pixels[bottomIndex]) * amount) / 255,
            green: (Double(pixels[topIndex + 1]) * inverse + Double(pixels[bottomIndex + 1]) * amount) / 255,
            blue: (Double(pixels[topIndex + 2]) * inverse + Double(pixels[bottomIndex + 2]) * amount) / 255
        )
    }

    private static func colorDistance(
        _ lhs: (red: Double, green: Double, blue: Double),
        _ rhs: (red: Double, green: Double, blue: Double)
    ) -> Double {
        let red = lhs.red - rhs.red
        let green = lhs.green - rhs.green
        let blue = lhs.blue - rhs.blue
        return sqrt(red * red + green * green + blue * blue)
    }

    private static func color(
        at index: Int,
        pixels: [UInt8]
    ) -> (red: Double, green: Double, blue: Double) {
        (
            red: Double(pixels[index]) / 255,
            green: Double(pixels[index + 1]) / 255,
            blue: Double(pixels[index + 2]) / 255
        )
    }

    private static func averageColor(
        at indexes: [Int],
        pixels: [UInt8]
    ) -> (red: Double, green: Double, blue: Double) {
        let colors = indexes.map { color(at: $0, pixels: pixels) }
        let count = Double(max(1, colors.count))
        return (
            red: colors.reduce(0) { $0 + $1.red } / count,
            green: colors.reduce(0) { $0 + $1.green } / count,
            blue: colors.reduce(0) { $0 + $1.blue } / count
        )
    }
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

    func averageColor(in rect: CGRect) -> NSColor? {
        let clipped = rect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1,
              let crop = cropping(to: clipped) else { return nil }
        let size = 12
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
        guard rendered else { return nil }

        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var count = 0.0
        for y in 0..<size {
            for x in 0..<size where x == 0 || y == 0 || x == size - 1 || y == size - 1 {
                let index = (y * size + x) * 4
                guard pixels[index + 3] > 20 else { continue }
                red += Double(pixels[index]) / 255
                green += Double(pixels[index + 1]) / 255
                blue += Double(pixels[index + 2]) / 255
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return NSColor(
            calibratedRed: red / count,
            green: green / count,
            blue: blue / count,
            alpha: 1
        )
    }
}

private extension NSColor {
    var relativeLuminance: Double {
        guard let rgb = usingColorSpace(.sRGB) else { return 1 }
        func linear(_ value: CGFloat) -> Double {
            let component = Double(value)
            return component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent)
            + 0.7152 * linear(rgb.greenComponent)
            + 0.0722 * linear(rgb.blueComponent)
    }

    func contrastRatio(againstLuminance other: Double) -> Double {
        let lighter = max(relativeLuminance, other)
        let darker = min(relativeLuminance, other)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

fileprivate enum OverlayDisplayMode {
    case original
    case translation
}

private struct TextRenderLayout {
    let textRect: CGRect
    let font: NSFont
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

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
