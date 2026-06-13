import AppKit
import CoreGraphics
import ServiceManagement

final class MainWindowController: NSObject, NSTextFieldDelegate {
    private var window: NSWindow?
    private var permissionStatusLabel: NSTextField?
    private var apiStatusLabel: NSTextField?
    private var launchAtLoginCheckbox: NSButton?
    private let apiEndpointField = NSTextField()
    private let apiKeyField = NSSecureTextField()
    private let modelField = NSTextField()
    private var pendingSave: DispatchWorkItem?

    private var onStartCapture: (() -> Void)?
    private var onOpenPermissions: (() -> Void)?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: TranslationSettings.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutDidChange),
            name: ShortcutRecorder.hotKeyChangedNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show(
        onStartCapture: @escaping () -> Void,
        onOpenPermissions: @escaping () -> Void
    ) {
        self.onStartCapture = onStartCapture
        self.onOpenPermissions = onOpenPermissions

        if window == nil {
            window = makeWindow()
        }

        loadSettings()
        refreshStatus()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ShotLens 控制台"
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 560))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        window.contentView = contentView

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.distribution = .fill
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -18)
        ])

        root.addArrangedSubview(makeHeader())
        root.addArrangedSubview(makePermissionCard())
        root.addArrangedSubview(makeShortcutCard())
        root.addArrangedSubview(makeStartupCard())
        root.addArrangedSubview(makeAPICard())
        root.addArrangedSubview(makeFooter())

        window.center()
        return window
    }

    private func makeHeader() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.widthAnchor.constraint(equalToConstant: 436).isActive = true

        let icon = ShotLensGlyphIconView(frame: NSRect(x: 0, y: 0, width: 44, height: 44))
        icon.widthAnchor.constraint(equalToConstant: 44).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        textStack.addArrangedSubview(label("ShotLens", font: .systemFont(ofSize: 24, weight: .semibold)))
        textStack.addArrangedSubview(label("截图翻译控制台 · 版本 \(displayVersion)", font: .systemFont(ofSize: 13), color: .secondaryLabelColor))

        row.addArrangedSubview(icon)
        row.addArrangedSubview(textStack)
        return row
    }

    private func makePermissionCard() -> NSView {
        let card = makeCard()
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.addArrangedSubview(label("屏幕录制权限", font: .systemFont(ofSize: 15, weight: .semibold)))
        textStack.addArrangedSubview(label("用于冻结屏幕和框选翻译。", font: .systemFont(ofSize: 12), color: .secondaryLabelColor))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let status = label("", font: .systemFont(ofSize: 13, weight: .semibold))
        permissionStatusLabel = status

        let button = NSButton(title: "打开设置", target: self, action: #selector(openPermissionsClicked))
        button.bezelStyle = .rounded

        row.addArrangedSubview(textStack)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(status)
        row.addArrangedSubview(button)
        card.addArrangedSubview(row)
        return card
    }

    private func makeStartupCard() -> NSView {
        let card = makeCard()
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.addArrangedSubview(label("开机自动启动", font: .systemFont(ofSize: 15, weight: .semibold)))
        textStack.addArrangedSubview(label("登录 Mac 后自动启动 ShotLens。", font: .systemFont(ofSize: 12), color: .secondaryLabelColor))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(launchAtLoginChanged))
        checkbox.state = launchAtLoginEnabled ? .on : .off
        launchAtLoginCheckbox = checkbox

        row.addArrangedSubview(textStack)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(checkbox)
        card.addArrangedSubview(row)
        return card
    }

    private func makeShortcutCard() -> NSView {
        let card = makeCard()
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.addArrangedSubview(label("快捷键", font: .systemFont(ofSize: 15, weight: .semibold)))
        textStack.addArrangedSubview(label("按下后直接进入截图框选。", font: .systemFont(ofSize: 12), color: .secondaryLabelColor))

        let recorder = ShortcutRecorder(frame: NSRect(x: 0, y: 0, width: 220, height: 32))
        recorder.widthAnchor.constraint(equalToConstant: 220).isActive = true
        recorder.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        row.addArrangedSubview(textStack)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(recorder)
        card.addArrangedSubview(row)
        return card
    }

    private func makeAPICard() -> NSView {
        let card = makeCard()
        card.spacing = 10
        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 10
        headerRow.widthAnchor.constraint(equalToConstant: 404).isActive = true

        headerRow.addArrangedSubview(label("API 翻译", font: .systemFont(ofSize: 15, weight: .semibold)))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerRow.addArrangedSubview(spacer)
        let clearButton = NSButton(title: "清空", target: self, action: #selector(clearAPISettingsClicked))
        clearButton.bezelStyle = .rounded
        clearButton.widthAnchor.constraint(equalToConstant: 58).isActive = true
        headerRow.addArrangedSubview(clearButton)
        let status = label("", font: .systemFont(ofSize: 12, weight: .semibold), color: .secondaryLabelColor)
        apiStatusLabel = status
        headerRow.addArrangedSubview(status)
        card.addArrangedSubview(headerRow)

        configureField(apiEndpointField, placeholder: "OpenAI-compatible chat completions endpoint")
        configureField(apiKeyField, placeholder: "API Key")
        configureField(modelField, placeholder: "model")

        card.addArrangedSubview(fieldRow("地址", field: apiEndpointField))
        card.addArrangedSubview(fieldRow("Key", field: apiKeyField))
        card.addArrangedSubview(fieldRow("模型", field: modelField))

        let note = label("所有翻译都走 API；OCR 会先按语义合并文本块。", font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        note.lineBreakMode = .byTruncatingTail
        card.addArrangedSubview(note)
        return card
    }

    private func makeFooter() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.widthAnchor.constraint(equalToConstant: 436).isActive = true

        let hint = label("设置会自动保存", font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let startButton = NSButton(title: "开始截图", target: self, action: #selector(startCaptureClicked))
        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"
        startButton.widthAnchor.constraint(equalToConstant: 110).isActive = true

        row.addArrangedSubview(hint)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(startButton)
        return row
    }

    private func makeCard() -> NSStackView {
        let card = NSStackView()
        card.orientation = .vertical
        card.alignment = .leading
        card.distribution = .fill
        card.spacing = 8
        card.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.widthAnchor.constraint(equalToConstant: 436).isActive = true
        return card
    }

    private func configureField(_ field: NSTextField, placeholder: String) {
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 13)
        field.delegate = self
        field.bezelStyle = .roundedBezel
        field.heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    private func fieldRow(_ title: String, field: NSTextField) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.widthAnchor.constraint(equalToConstant: 404).isActive = true

        let titleLabel = label(title, font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        titleLabel.widthAnchor.constraint(equalToConstant: 38).isActive = true
        field.widthAnchor.constraint(equalToConstant: 356).isActive = true

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(field)
        return row
    }

    private func label(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        return field
    }

    private var displayVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let normalized = shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else { return "v1.0" }
        if normalized.hasPrefix("v") { return normalized }
        if normalized.hasPrefix("V") { return "v\(normalized.dropFirst())" }
        return "v\(normalized)"
    }

    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func loadSettings() {
        let settings = TranslationSettings.load()
        apiEndpointField.stringValue = settings.apiEndpoint
        apiKeyField.stringValue = settings.apiKey
        modelField.stringValue = settings.model
        launchAtLoginCheckbox?.state = launchAtLoginEnabled ? .on : .off
    }

    private func refreshStatus() {
        if CGPreflightScreenCaptureAccess() {
            permissionStatusLabel?.stringValue = "● 已开启"
            permissionStatusLabel?.textColor = .systemGreen
        } else {
            permissionStatusLabel?.stringValue = "● 未开启"
            permissionStatusLabel?.textColor = .systemOrange
        }

        let settings = currentDraftSettings()
        if settings.isLLMConfigured {
            apiStatusLabel?.stringValue = "● 可用"
            apiStatusLabel?.textColor = .systemGreen
        } else {
            apiStatusLabel?.stringValue = "● 未配置"
            apiStatusLabel?.textColor = .secondaryLabelColor
        }
    }

    private func currentDraftSettings() -> TranslationSettings {
        TranslationSettings(
            apiEndpoint: apiEndpointField.stringValue,
            apiKey: apiKeyField.stringValue,
            model: modelField.stringValue
        )
    }

    private func saveSettingsSoon() {
        pendingSave?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.currentDraftSettings().save()
            self.refreshStatus()
        }
        pendingSave = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    @objc private func startCaptureClicked() {
        pendingSave?.perform()
        onStartCapture?()
    }

    @objc private func openPermissionsClicked() {
        onOpenPermissions?()
    }

    @objc private func launchAtLoginChanged() {
        let shouldEnable = launchAtLoginCheckbox?.state == .on
        do {
            if shouldEnable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginCheckbox?.state = launchAtLoginEnabled ? .on : .off
            ShotLensLogger.log("更新开机自动启动失败", error: error)
        }
    }

    @objc private func clearAPISettingsClicked() {
        pendingSave?.cancel()
        TranslationSettings.resetSavedConfiguration()
        loadSettings()
        refreshStatus()
    }

    @objc private func settingsDidChange() {
        refreshStatus()
    }

    @objc private func shortcutDidChange() {}

    @objc private func appDidBecomeActive() {
        refreshStatus()
    }

    func controlTextDidChange(_ obj: Notification) {
        refreshStatus()
        saveSettingsSoon()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        pendingSave?.cancel()
        currentDraftSettings().save()
        refreshStatus()
    }
}

private final class ShotLensGlyphIconView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height)
        let rect = NSRect(
            x: bounds.midX - side / 2,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        )

        NSColor(calibratedRed: 0.035, green: 0.039, blue: 0.044, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: side * 0.25, yRadius: side * 0.25).fill()

        let text = "译" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: side * 0.48, weight: .black),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2 + side * 0.02,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
    }
}
