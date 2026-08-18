import Foundation

enum OverlayPinAppearance {
    static func usesDarkSymbol(backgroundLuminance: Double) -> Bool {
        backgroundLuminance >= 0.55
    }

    /// 通过空心/实心表达钉住状态，不旋转图形，避免非整数像素重采样。
    static func symbolRotationDegrees(isPinned: Bool) -> Double {
        0
    }
}
