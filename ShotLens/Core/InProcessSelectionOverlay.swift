import AppKit
import CoreGraphics

@MainActor
final class InProcessSelectionOverlay {
    private var windows: [InProcessSelectionWindow] = []
    private var keyMonitor: Any?
    private var continuation: CheckedContinuation<CGRect?, Never>?
    private var didFinish = false

    func select(frozenScreenshot: FrozenScreenshot?) async -> CGRect? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            show(frozenScreenshot: frozenScreenshot)
        }
    }

    private func show(frozenScreenshot: FrozenScreenshot?) {
        let screens = NSScreen.screens
        let targetScreen = frozenScreenshot.flatMap { snapshot in
            screens.first { $0.frame == snapshot.screenRect }
        } ?? screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen = targetScreen else {
            finish(with: nil)
            return
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    self?.finish(with: nil)
                }
                return nil
            }
            return event
        }

        let window = InProcessSelectionWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.onCancel = { [weak self] in
            self?.finish(with: nil)
        }

        let view = InProcessSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.screenOrigin = screen.frame.origin
        view.backgroundImage = frozenScreenshot?.image
        view.onComplete = { [weak self] rect in
            self?.finish(with: rect)
        }
        window.contentView = view
        window.orderFrontRegardless()
        window.makeKey()
        windows.append(window)
    }

    private func finish(with rect: CGRect?) {
        guard !didFinish else { return }
        didFinish = true

        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }

        let windows = self.windows
        self.windows = []
        windows.forEach { $0.close() }

        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: rect)
    }
}

private final class InProcessSelectionWindow: NSPanel {
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

private final class InProcessSelectionView: NSView {
    var screenOrigin: CGPoint = .zero
    var backgroundImage: CGImage?
    var onComplete: ((CGRect?) -> Void)?

    private var startPoint: CGPoint = .zero
    private var selectionRect: CGRect?
    private var isDragging = false

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        if let backgroundImage {
            NSImage(cgImage: backgroundImage, size: bounds.size).draw(in: bounds)
        }

        NSColor.black.withAlphaComponent(0.36).setFill()
        bounds.fill()

        if let selectionRect {
            NSColor.white.withAlphaComponent(0.12).setFill()
            selectionRect.fill()
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selectionRect)
            border.lineWidth = 1
            border.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        selectionRect = nil
        isDragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let current = convert(event.locationInWindow, from: nil)
        selectionRect = CGRect(
            x: min(startPoint.x, current.x),
            y: min(startPoint.y, current.y),
            width: abs(current.x - startPoint.x),
            height: abs(current.y - startPoint.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false

        guard let rect = selectionRect,
              rect.width >= 20,
              rect.height >= 20 else {
            onComplete?(nil)
            return
        }

        let screenRect = CGRect(
            x: rect.origin.x + screenOrigin.x,
            y: screenOrigin.y + bounds.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        onComplete?(screenRect)
    }
}
