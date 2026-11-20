import AppKit
import CoreGraphics

@main
struct ClipboardManagerSmoke {
    @MainActor
    static func main() async throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 3,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestFailure("Unable to create test image context")
        }
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
        guard let image = context.makeImage() else {
            throw TestFailure("Unable to create test image")
        }

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ShotLensClipboardTest-\(UUID().uuidString)"))
        await ClipboardManager().copyImageToClipboard(image: image, pasteboard: pasteboard)

        guard let pngData = pasteboard.data(forType: .png),
              let bitmap = NSBitmapImageRep(data: pngData),
              bitmap.pixelsWide == 3,
              bitmap.pixelsHigh == 2 else {
            throw TestFailure("Expected the selected screenshot PNG on the pasteboard")
        }
        guard pasteboard.string(forType: .string) == nil else {
            throw TestFailure("Automatic selection copy should contain only the screenshot")
        }

        let textPasteboard = NSPasteboard(name: NSPasteboard.Name("ShotLensTextClipboardTest-\(UUID().uuidString)"))
        ClipboardManager().copyTextToClipboard("设置", pasteboard: textPasteboard)
        guard textPasteboard.string(forType: .string) == "设置" else {
            throw TestFailure("Text copy should write the translated Chinese text")
        }
        guard textPasteboard.data(forType: .png) == nil else {
            throw TestFailure("Text-only copy should not write an image")
        }

        print("Clipboard manager smoke test passed.")
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
