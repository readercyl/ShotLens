import AppKit
import CoreGraphics
import Darwin
import ImageIO

@main
final class ShotLensSelect: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []

    static func main() {
        let app = NSApplication.shared
        let delegate = ShotLensSelect()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            Self.write(cancelled: true)
        }
        let frozenSnapshot = FrozenSelectionSnapshot.fromCommandLine()

        for screen in screens {
            let window = SelectionWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.onCancel = {
                Self.write(cancelled: true)
            }

            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.screenOrigin = screen.frame.origin
            view.backgroundImage = frozenSnapshot?.cropForScreen(screen.frame)
            view.onComplete = { rect in
                Self.write(rect: rect)
            }
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    private static func write(rect: CGRect) -> Never {
        let json = """
        {"cancelled":false,"x":\(rect.origin.x),"y":\(rect.origin.y),"width":\(rect.width),"height":\(rect.height)}
        """
        FileHandle.standardOutput.write(Data(json.utf8))
        fflush(stdout)
        exit(0)
    }

    private static func write(cancelled: Bool) -> Never {
        let json = #"{"cancelled":true}"#
        FileHandle.standardOutput.write(Data(json.utf8))
        fflush(stdout)
        exit(0)
    }
}

private struct FrozenSelectionSnapshot {
    let image: CGImage
    let screenRect: CGRect

    static func fromCommandLine() -> FrozenSelectionSnapshot? {
        let args = CommandLine.arguments
        guard let imagePath = value(after: "--frozen-image", in: args),
              let screenX = number(after: "--screen-x", in: args),
              let screenY = number(after: "--screen-y", in: args),
              let screenWidth = number(after: "--screen-width", in: args),
              let screenHeight = number(after: "--screen-height", in: args),
              screenWidth > 0,
              screenHeight > 0 else {
            return nil
        }

        let url = URL(fileURLWithPath: imagePath)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        return FrozenSelectionSnapshot(
            image: image,
            screenRect: CGRect(x: screenX, y: screenY, width: screenWidth, height: screenHeight)
        )
    }

    func cropForScreen(_ screenFrame: CGRect) -> CGImage? {
        let visibleFrame = screenFrame.intersection(screenRect)
        guard !visibleFrame.isNull,
              visibleFrame.width > 0,
              visibleFrame.height > 0 else {
            return nil
        }

        let scaleX = CGFloat(image.width) / max(screenRect.width, 1)
        let scaleY = CGFloat(image.height) / max(screenRect.height, 1)
        let minX = max(0, floor((visibleFrame.minX - screenRect.minX) * scaleX))
        let maxX = min(CGFloat(image.width), ceil((visibleFrame.maxX - screenRect.minX) * scaleX))
        let minY = max(0, floor((screenRect.maxY - visibleFrame.maxY) * scaleY))
        let maxY = min(CGFloat(image.height), ceil((screenRect.maxY - visibleFrame.minY) * scaleY))

        guard maxX > minX, maxY > minY else {
            return nil
        }

        return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag),
              args.indices.contains(index + 1) else {
            return nil
        }
        return args[index + 1]
    }

    private static func number(after flag: String, in args: [String]) -> CGFloat? {
        guard let text = value(after: flag, in: args),
              let value = Double(text) else {
            return nil
        }
        return CGFloat(value)
    }
}

private final class SelectionWindow: NSPanel {
    var onCancel: (() -> Never)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            _ = onCancel?()
            return
        }
        super.keyDown(with: event)
    }
}

private final class SelectionView: NSView {
    var screenOrigin: CGPoint = .zero
    var backgroundImage: CGImage?
    var onComplete: ((CGRect) -> Never)?

    private var startPoint: CGPoint = .zero
    private var selectionRect: CGRect?
    private var isDragging = false

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

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
            SelfCancel.write()
        }

        let screenRect = CGRect(
            x: rect.origin.x + screenOrigin.x,
            y: screenOrigin.y + bounds.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        _ = onComplete?(screenRect)
    }
}

private enum SelfCancel {
    static func write() -> Never {
        let json = #"{"cancelled":true}"#
        FileHandle.standardOutput.write(Data(json.utf8))
        fflush(stdout)
        exit(0)
    }
}
