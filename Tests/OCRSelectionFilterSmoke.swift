import AppKit
import Foundation

@main
struct OCRSelectionFilterSmoke {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw TestFailure("Missing OCR helper path")
        }
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shotlens-ocr-selection-filter.png")
        try makeTestImage().writePNG(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
        process.arguments = [imageURL.path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw TestFailure("OCR helper failed")
        }

        let blocks = try JSONDecoder().decode(
            [OCRBlock].self,
            from: output.fileHandleForReading.readDataToEndOfFile()
        )
        let texts = blocks.map(\.text)
        guard texts.contains("Complete"), texts.contains("English"), texts.contains("Text") else {
            throw TestFailure("Fully selected English words were not preserved: \(texts)")
        }
        guard texts.contains("Light"), texts.contains("Contrast"), texts.contains("Text") else {
            throw TestFailure("Low-contrast light English words were not recognized: \(texts)")
        }
        guard texts.contains("GPT-4o"), texts.contains("API"), texts.contains("v2.5") else {
            throw TestFailure("Technical identifiers were changed or omitted: \(texts)")
        }
        guard texts.contains("English"), texts.contains("More") else {
            throw TestFailure("Mixed-language lines must keep English runs: \(texts)")
        }
        guard !texts.contains(where: { $0.contains("中文") || $0 == "X" || $0 == "#" }) else {
            throw TestFailure("Chinese or OCR noise must not be emitted as English: \(texts)")
        }
        guard !texts.contains(where: { $0.localizedCaseInsensitiveContains("boundary") }) else {
            throw TestFailure("Text clipped by the selection boundary must be ignored: \(texts)")
        }
        guard !texts.contains(where: { $0 == "● ± □" }) else {
            throw TestFailure("Pure icon and symbol noise must be excluded: \(texts)")
        }

        print("OCR selection filter smoke test passed.")
    }

    private static func makeTestImage() -> NSImage {
        let size = NSSize(width: 1_400, height: 800)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 54, weight: .medium),
            .foregroundColor: NSColor.black
        ]
        ("Complete English Text" as NSString).draw(
            at: NSPoint(x: 100, y: 610),
            withAttributes: attributes
        )
        ("中文 English 中文 More" as NSString).draw(
            at: NSPoint(x: 100, y: 390),
            withAttributes: attributes
        )
        ("GPT-4o API v2.5" as NSString).draw(
            at: NSPoint(x: 100, y: 500),
            withAttributes: attributes
        )
        NSColor(calibratedWhite: 0.22, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 80, y: 255, width: 900, height: 105)).fill()
        ("Light Contrast Text" as NSString).draw(
            at: NSPoint(x: 100, y: 275),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 54, weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 0.48, alpha: 1)
            ]
        )
        ("IncompleteBoundary" as NSString).draw(
            at: NSPoint(x: -330, y: 170),
            withAttributes: attributes
        )
        ("● ± □" as NSString).draw(
            at: NSPoint(x: 1_050, y: 170),
            withAttributes: attributes
        )
        image.unlockFocus()
        return image
    }
}

private struct OCRBlock: Decodable {
    let text: String
}

private struct TestFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

private extension NSImage {
    func writePNG(to url: URL) throws {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            throw TestFailure("Unable to encode OCR test image")
        }
        try data.write(to: url)
    }
}
