import AppKit
import CoreGraphics

/// 剪贴板管理器。截图和文本使用互斥入口，避免粘贴目标选错数据类型。
struct ClipboardManager {
    /// 将刚完成框选的原始截图写入系统剪贴板。
    /// 整屏 PNG 编码在 6K 屏上可达数百毫秒，放到后台编码后再写剪贴板。
    @MainActor
    func copyImageToClipboard(image: CGImage, pasteboard: NSPasteboard = .general) async {
        let pngData = await Task.detached(priority: .userInitiated) { () -> Data? in
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        }.value
        guard let pngData else { return }
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
    }

    /// 只复制译文文本，不写入图片。
    func copyTextToClipboard(_ text: String, pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
