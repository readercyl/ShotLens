import Foundation

enum OverlayPinAppearance {
    static func usesDarkSymbol(backgroundLuminance: Double) -> Bool {
        backgroundLuminance >= 0.55
    }

    /// SF Symbols 的 pin 默认斜向约 45°；未钉住时反向旋转为竖直。
    static func symbolRotationDegrees(isPinned: Bool) -> Double {
        isPinned ? 0 : -45
    }
}
