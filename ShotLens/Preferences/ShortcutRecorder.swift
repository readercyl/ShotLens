import AppKit
import Carbon

/// 全局快捷键的数据模型
struct HotKey: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int

    var displayString: String {
        var parts: [String] = []
        if modifiers & cmdKey != 0 { parts.append("⌘") }
        if modifiers & optionKey != 0 { parts.append("⌥") }
        if modifiers & controlKey != 0 { parts.append("⌃") }
        if modifiers & shiftKey != 0 { parts.append("⇧") }
        if let keyChar = keyCodeToDisplayString(keyCode) {
            parts.append(keyChar.uppercased())
        }
        return parts.joined(separator: " ")
    }

    static let storageKey = "ShotLens_GlobalHotKey"
    static let `default` = HotKey(keyCode: 1, modifiers: optionKey)

    private static let supportedModifierMask = cmdKey | optionKey | controlKey | shiftKey

    var isValidForRegistration: Bool {
        keyCode >= 0 &&
            keyCode < 128 &&
            keyCode != 53 &&
            modifiers & Self.supportedModifierMask != 0 &&
            modifiers & ~Self.supportedModifierMask == 0
    }

    static func loadSavedOrDefault(from defaults: UserDefaults = .standard) -> HotKey {
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(HotKey.self, from: data),
           saved.isValidForRegistration {
            return saved
        }

        let fallback = HotKey.default
        fallback.save(to: defaults)
        return fallback
    }

    @discardableResult
    func save(to defaults: UserDefaults = .standard) -> Bool {
        guard let data = try? JSONEncoder().encode(self) else {
            return false
        }
        defaults.set(data, forKey: Self.storageKey)
        return true
    }

    /// 将 NSEvent modifierFlags 转为 Carbon 修饰键编码
    /// NSEvent: .option = 0x80000, Carbon: optionKey = 0x0800
    static func carbonModifiers(from nseventModifiers: NSEvent.ModifierFlags) -> Int {
        var carbon: Int = 0
        if nseventModifiers.contains(.command) { carbon |= cmdKey }
        if nseventModifiers.contains(.shift)   { carbon |= shiftKey }
        if nseventModifiers.contains(.option)  { carbon |= optionKey }
        if nseventModifiers.contains(.control) { carbon |= controlKey }
        return carbon
    }

    private func keyCodeToDisplayString(_ code: Int) -> String? {
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let dataRef = unsafeBitCast(layoutData, to: CFData.self)
        let ptr = CFDataGetBytePtr(dataRef).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { $0 }

        var deadKeyState: UInt32 = 0
        let maxChars = 4
        var chars = [UniChar](repeating: 0, count: maxChars)
        var actualLen = 0

        UCKeyTranslate(
            ptr,
            UInt16(code),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            maxChars,
            &actualLen,
            &chars
        )

        if actualLen > 0 {
            return String(utf16CodeUnits: chars, count: actualLen)
        }
        return nil
    }
}

/// 快捷键录制控件：默认显示当前快捷键，只有点击“设置”后才接收新的组合键。
final class ShortcutRecorder: NSView {
    var onShortcutChanged: ((HotKey) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private let resetButton = NSButton(title: "默认", target: nil, action: nil)
    private let actionButton = NSButton(title: "设置", target: nil, action: nil)
    private var isRecording = false
    private var recordingHint = "按新快捷键"
    private var currentHotKey: HotKey = .default {
        didSet {
            updateLabel()
            onShortcutChanged?(currentHotKey)
            save()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupView()
        load()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        return true
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            stopRecording()
        }
        return true
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.978, green: 0.982, blue: 0.989, alpha: 1).cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedRed: 0.800, green: 0.828, blue: 0.866, alpha: 1).cgColor

        label.alignment = .center
        label.font = NSFont.monospacedSystemFont(ofSize: 17, weight: .semibold)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        addSubview(label)

        resetButton.target = self
        resetButton.action = #selector(resetToDefault)
        applySecondaryButtonStyle(resetButton)
        addSubview(resetButton)

        actionButton.target = self
        actionButton.action = #selector(toggleRecording)
        applySecondaryButtonStyle(actionButton)
        addSubview(actionButton)

        updateLabel()
    }

    override func layout() {
        super.layout()
        let gap: CGFloat = 4
        let buttonWidth: CGFloat = 54
        let buttonFrame = NSRect(
            x: bounds.maxX - buttonWidth - 4,
            y: 4,
            width: buttonWidth,
            height: max(24, bounds.height - 8)
        )
        actionButton.frame = buttonFrame

        let resetWidth: CGFloat = resetButton.isHidden ? 0 : 48
        let resetMinX = resetButton.isHidden ? buttonFrame.minX : buttonFrame.minX - gap - resetWidth
        resetButton.frame = NSRect(
            x: resetMinX,
            y: 4,
            width: resetWidth,
            height: max(24, bounds.height - 8)
        )

        label.frame = NSRect(
            x: 8,
            y: 4,
            width: max(0, resetMinX - 14),
            height: max(24, bounds.height - 8)
        )
    }

    private func updateLabel() {
        label.stringValue = isRecording ? recordingHint : currentHotKey.displayString
        label.textColor = isRecording ? .secondaryLabelColor : .labelColor
        resetButton.isHidden = isRecording || currentHotKey == .default
        actionButton.title = isRecording ? "取消" : "设置"
        layer?.borderColor = isRecording
            ? NSColor(calibratedRed: 0.180, green: 0.190, blue: 0.205, alpha: 0.45).cgColor
            : NSColor(calibratedRed: 0.800, green: 0.828, blue: 0.866, alpha: 1).cgColor
        needsLayout = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    @objc private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    @objc private func resetToDefault() {
        if isRecording {
            stopRecording()
        }
        guard currentHotKey != .default else { return }
        currentHotKey = .default
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        recordingHint = "按新快捷键"
        window?.makeFirstResponder(self)
        NotificationCenter.default.post(name: ShortcutRecorder.recordingDidBeginNotification, object: nil)
        updateLabel()
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        recordingHint = "按新快捷键"
        NotificationCenter.default.post(name: ShortcutRecorder.recordingDidEndNotification, object: nil)
        updateLabel()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }
        return recordShortcut(from: event)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        _ = recordShortcut(from: event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }

        let modifiers = HotKey.carbonModifiers(from: event.modifierFlags)
        recordingHint = modifierHint(for: modifiers)
        updateLabel()
    }

    private func recordShortcut(from event: NSEvent) -> Bool {
        // Esc 取消录制
        if event.keyCode == 53 {
            window?.makeFirstResponder(nil)
            return true
        }

        let modifiers = HotKey.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            recordingHint = "请按组合键"
            updateLabel()
            return true
        }

        let keyCode = Int(event.keyCode)
        currentHotKey = HotKey(keyCode: keyCode, modifiers: modifiers)
        stopRecording()
        window?.makeFirstResponder(nil)
        return true
    }

    private func modifierHint(for modifiers: Int) -> String {
        var parts: [String] = []
        if modifiers & cmdKey != 0 { parts.append("⌘") }
        if modifiers & optionKey != 0 { parts.append("⌥") }
        if modifiers & controlKey != 0 { parts.append("⌃") }
        if modifiers & shiftKey != 0 { parts.append("⇧") }
        return parts.isEmpty ? "按新快捷键" : parts.joined(separator: " ") + " ..."
    }

    override func cancelOperation(_ sender: Any?) {
        // Esc 也走这里（备用）
        if isRecording {
            window?.makeFirstResponder(nil)
        }
    }

    static let hotKeyChangedNotification = Notification.Name("ShotLensHotKeyChanged")
    static let recordingDidBeginNotification = Notification.Name("ShotLensHotKeyRecordingDidBegin")
    static let recordingDidEndNotification = Notification.Name("ShotLensHotKeyRecordingDidEnd")

    private func save() {
        if currentHotKey.save() {
            // 通知 AppDelegate 重新注册全局快捷键
            NotificationCenter.default.post(name: ShortcutRecorder.hotKeyChangedNotification, object: currentHotKey)
        }
    }

    private func load() {
        currentHotKey = HotKey.loadSavedOrDefault()
    }
}
