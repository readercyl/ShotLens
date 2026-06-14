import AppKit
import CoreGraphics
import ServiceManagement

final class MainWindowController: NSObject, NSTextFieldDelegate {
    private var window: NSWindow?
    private var permissionStatusLabel: NSTextField?
    private var apiStatusLabel: NSTextField?
    private var updateStatusLabel: NSTextField?
    private var launchAtLoginCheckbox: NSButton?
    private let checkUpdateButton = NSButton()
    private let installUpdateButton = NSButton()
    private let apiEndpointField = NSTextField()
    private let apiKeyField = NSTextField()
    private var apiKeyValue = ""
    private let apiKeyEyeButton = NSButton()
    private var isApiKeyVisible = false
    private var apiKeyAutoRevealed = false
    private let modelField = NSTextField()
    private let modelArrowButton = NSButton()
    private var availableModels: [String] = []

    private enum ConnectionState {
        case notConfigured
        case untested
        case testing
        case available
        case unavailable
    }
    private var connectionState: ConnectionState = .untested
    private var connectionTestTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var availableUpdate: AppUpdate?

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
        textStack.addArrangedSubview(makeVersionRow())

        row.addArrangedSubview(icon)
        row.addArrangedSubview(textStack)
        return row
    }

    private func makeVersionRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6

        row.addArrangedSubview(label("截图翻译控制台 · 版本 \(displayVersion)", font: .systemFont(ofSize: 13), color: .secondaryLabelColor))

        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        checkUpdateButton.bezelStyle = .inline
        checkUpdateButton.isBordered = false
        checkUpdateButton.imagePosition = .imageOnly
        checkUpdateButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "检查更新")?.withSymbolConfiguration(config)
        checkUpdateButton.toolTip = "检查新版本"
        checkUpdateButton.target = self
        checkUpdateButton.action = #selector(checkForUpdatesClicked)
        checkUpdateButton.widthAnchor.constraint(equalToConstant: 22).isActive = true
        checkUpdateButton.heightAnchor.constraint(equalToConstant: 22).isActive = true
        row.addArrangedSubview(checkUpdateButton)

        let status = label("", font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        status.lineBreakMode = .byTruncatingTail
        updateStatusLabel = status
        row.addArrangedSubview(status)

        installUpdateButton.title = "升级"
        installUpdateButton.bezelStyle = .rounded
        installUpdateButton.target = self
        installUpdateButton.action = #selector(installUpdateClicked)
        installUpdateButton.isHidden = true
        installUpdateButton.widthAnchor.constraint(equalToConstant: 58).isActive = true
        row.addArrangedSubview(installUpdateButton)

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

        headerRow.addArrangedSubview(label("API 信息", font: .systemFont(ofSize: 15, weight: .semibold)))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerRow.addArrangedSubview(spacer)
        let clearButton = NSButton(title: "清空", target: self, action: #selector(clearAPISettingsClicked))
        clearButton.bezelStyle = .rounded
        clearButton.widthAnchor.constraint(equalToConstant: 58).isActive = true
        headerRow.addArrangedSubview(clearButton)
        let testButton = NSButton(title: "测试", target: self, action: #selector(testConnectionClicked))
        testButton.bezelStyle = .rounded
        testButton.widthAnchor.constraint(equalToConstant: 58).isActive = true
        headerRow.addArrangedSubview(testButton)
        let status = label("", font: .systemFont(ofSize: 12, weight: .semibold), color: .secondaryLabelColor)
        apiStatusLabel = status
        headerRow.addArrangedSubview(status)
        card.addArrangedSubview(headerRow)

        configureField(apiEndpointField, placeholder: "")
        configureField(modelField, placeholder: "")

        card.addArrangedSubview(fieldRow("地址", field: apiEndpointField))
        card.addArrangedSubview(apiKeyFieldRow())
        card.addArrangedSubview(modelFieldRow())

        let note = label("Key 留空时使用默认福利额度；\(TranslationSettings.limitedFreeModelNotice)", font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
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

    private func apiKeyFieldRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.widthAnchor.constraint(equalToConstant: 404).isActive = true

        let titleLabel = label("Key", font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        titleLabel.widthAnchor.constraint(equalToConstant: 38).isActive = true

        // 普通 NSTextField，不触发系统密码提示
        apiKeyField.font = .systemFont(ofSize: 13)
        apiKeyField.delegate = self
        apiKeyField.bezelStyle = .roundedBezel
        apiKeyField.cell?.wraps = false
        apiKeyField.cell?.isScrollable = true
        apiKeyField.usesSingleLineMode = true
        apiKeyField.lineBreakMode = .byTruncatingTail
        apiKeyField.translatesAutoresizingMaskIntoConstraints = false

        // 外层容器 356×28
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalToConstant: 356).isActive = true
        container.heightAnchor.constraint(equalToConstant: 28).isActive = true

        // 文本框 328，眼图标间距 6
        container.addSubview(apiKeyField)
        NSLayoutConstraint.activate([
            apiKeyField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            apiKeyField.widthAnchor.constraint(equalToConstant: 328),
            apiKeyField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            apiKeyField.heightAnchor.constraint(equalToConstant: 28),
        ])

        // 眼图标
        apiKeyEyeButton.bezelStyle = .inline
        apiKeyEyeButton.isBordered = false
        apiKeyEyeButton.imagePosition = .imageOnly
        apiKeyEyeButton.target = self
        apiKeyEyeButton.action = #selector(toggleApiKeyVisibility)
        apiKeyEyeButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(apiKeyEyeButton)
        NSLayoutConstraint.activate([
            apiKeyEyeButton.leadingAnchor.constraint(equalTo: apiKeyField.trailingAnchor, constant: 6),
            apiKeyEyeButton.widthAnchor.constraint(equalToConstant: 22),
            apiKeyEyeButton.heightAnchor.constraint(equalToConstant: 22),
            apiKeyEyeButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        updateApiKeyEyeIcon()

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(container)
        return row
    }

    @objc private func toggleApiKeyVisibility() {
        apiKeyAutoRevealed = false
        isApiKeyVisible.toggle()
        updateApiKeyDisplay()
        updateApiKeyEyeIcon()
    }

    private func updateApiKeyDisplay() {
        apiKeyField.stringValue = isApiKeyVisible
            ? apiKeyValue
            : String(repeating: "•", count: apiKeyValue.count)
    }

    private func updateApiKeyEyeIcon() {
        let symbolName = isApiKeyVisible ? "eye.slash" : "eye"
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        apiKeyEyeButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        // 点击密文 Key 输入框时自动显示明文
        if obj.object as? NSTextField === apiKeyField, !isApiKeyVisible {
            isApiKeyVisible = true
            apiKeyAutoRevealed = true
            updateApiKeyDisplay()
            updateApiKeyEyeIcon()
        }
    }


    private func modelFieldRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.widthAnchor.constraint(equalToConstant: 404).isActive = true

        let titleLabel = label("模型", font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        titleLabel.widthAnchor.constraint(equalToConstant: 38).isActive = true

        // 外层容器 356×28
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalToConstant: 356).isActive = true
        container.heightAnchor.constraint(equalToConstant: 28).isActive = true

        // 文本框 328，箭头在右侧间距 6
        modelField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(modelField)
        NSLayoutConstraint.activate([
            modelField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            modelField.widthAnchor.constraint(equalToConstant: 328),
            modelField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            modelField.heightAnchor.constraint(equalToConstant: 28),
        ])

        // 下拉箭头
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        modelArrowButton.bezelStyle = .inline
        modelArrowButton.isBordered = false
        modelArrowButton.imagePosition = .imageOnly
        modelArrowButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(config)
        modelArrowButton.target = self
        modelArrowButton.action = #selector(modelArrowClicked)
        modelArrowButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(modelArrowButton)
        NSLayoutConstraint.activate([
            modelArrowButton.leadingAnchor.constraint(equalTo: modelField.trailingAnchor, constant: 6),
            modelArrowButton.widthAnchor.constraint(equalToConstant: 22),
            modelArrowButton.heightAnchor.constraint(equalToConstant: 22),
            modelArrowButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(container)
        return row
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
        apiKeyValue = settings.apiKey
        isApiKeyVisible = false
        apiKeyAutoRevealed = false
        updateApiKeyDisplay()
        updateApiKeyEyeIcon()
        modelField.stringValue = settings.model
        launchAtLoginCheckbox?.state = launchAtLoginEnabled ? .on : .off

        // 不自动测试，等用户手动点击「测试」按钮
        connectionState = .untested
        refreshStatus()
    }

    private func refreshStatus() {
        if CGPreflightScreenCaptureAccess() {
            permissionStatusLabel?.stringValue = "● 已开启"
            permissionStatusLabel?.textColor = .systemGreen
        } else {
            permissionStatusLabel?.stringValue = "● 未开启"
            permissionStatusLabel?.textColor = .systemOrange
        }

        switch connectionState {
        case .notConfigured:
            apiStatusLabel?.stringValue = "● 默认额度"
            apiStatusLabel?.textColor = .secondaryLabelColor
        case .untested:
            let settings = currentDraftSettings()
            apiStatusLabel?.stringValue = settings.usesDefaultAPIKey ? "● 默认额度" : "● 未测试"
            apiStatusLabel?.textColor = .secondaryLabelColor
        case .testing:
            apiStatusLabel?.stringValue = "● 测试中…"
            apiStatusLabel?.textColor = .secondaryLabelColor
        case .available:
            apiStatusLabel?.stringValue = "● 可用"
            apiStatusLabel?.textColor = .systemGreen
        case .unavailable:
            apiStatusLabel?.stringValue = "● 不可用"
            apiStatusLabel?.textColor = .systemRed
        }
    }

    func currentDraftSettings() -> TranslationSettings {
        TranslationSettings(
            apiEndpoint: apiEndpointField.stringValue,
            apiKey: apiKeyValue,
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
        flushPendingSave()
        onStartCapture?()
    }

    /// 强制保存当前草稿设置，确保翻译时 UserDefaults 是最新的
    func flushPendingSave() {
        pendingSave?.perform()
        pendingSave?.cancel()
        pendingSave = nil
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

    @objc private func testConnectionClicked() {
        connectionTestTask?.cancel()
        // 先无条件显示"测试中…"，让用户感知按钮已被触发
        connectionState = .testing
        refreshStatus()
        testConnection()
    }

    @objc private func clearAPISettingsClicked() {
        pendingSave?.cancel()
        TranslationSettings.resetSavedConfiguration()
        connectionState = .untested
        availableModels = []
        apiKeyValue = ""
        isApiKeyVisible = false
        apiKeyAutoRevealed = false
        loadSettings()
        refreshStatus()
    }

    // MARK: - 更新检查

    @objc private func checkForUpdatesClicked() {
        updateTask?.cancel()
        availableUpdate = nil
        installUpdateButton.isHidden = true
        checkUpdateButton.isEnabled = false
        updateStatusLabel?.stringValue = "检查中…"
        updateStatusLabel?.textColor = .secondaryLabelColor

        updateTask = Task { [weak self] in
            let result = await AppUpdater().checkForUpdate()
            guard !Task.isCancelled, let controller = self else { return }
            await MainActor.run {
                controller.applyUpdateCheckResult(result)
            }
        }
    }

    private func applyUpdateCheckResult(_ result: AppUpdateCheckResult) {
        checkUpdateButton.isEnabled = true
        switch result {
        case .available(let update):
            availableUpdate = update
            updateStatusLabel?.stringValue = "发现 \(update.version)"
            updateStatusLabel?.textColor = .systemGreen
            installUpdateButton.isHidden = false
        case .upToDate:
            availableUpdate = nil
            updateStatusLabel?.stringValue = "已是最新版"
            updateStatusLabel?.textColor = .secondaryLabelColor
            installUpdateButton.isHidden = true
        case .failed:
            availableUpdate = nil
            updateStatusLabel?.stringValue = "无法连接更新服务器"
            updateStatusLabel?.textColor = .systemOrange
            installUpdateButton.isHidden = true
        }
    }

    @objc private func installUpdateClicked() {
        guard let update = availableUpdate else { return }
        checkUpdateButton.isEnabled = false
        installUpdateButton.isEnabled = false
        updateStatusLabel?.stringValue = "下载中…"
        updateStatusLabel?.textColor = .secondaryLabelColor

        updateTask?.cancel()
        updateTask = Task { [weak self] in
            do {
                let updater = AppUpdater()
                let dmgURL = try await updater.download(update)
                guard !Task.isCancelled, let controller = self else { return }
                await MainActor.run {
                    do {
                        try updater.installDownloadedUpdate(from: dmgURL)
                    } catch {
                        controller.showUpdateInstallFailure()
                    }
                }
            } catch {
                guard let controller = self else { return }
                await MainActor.run {
                    controller.showUpdateInstallFailure()
                }
            }
        }
    }

    private func showUpdateInstallFailure() {
        checkUpdateButton.isEnabled = true
        installUpdateButton.isEnabled = true
        updateStatusLabel?.stringValue = "升级失败，请使用发布文档"
        updateStatusLabel?.textColor = .systemRed
    }

    private func markUntested() {
        connectionState = .untested
        availableModels = []
        refreshStatus()
    }

    // MARK: - 连接测试

    private var canTestConnection: Bool {
        currentDraftSettings().isLLMConfigured
    }

    private func scheduleConnectionTest() {
        guard canTestConnection else {
            connectionState = .notConfigured
            refreshStatus()
            return
        }
        connectionState = .testing
        refreshStatus()

        connectionTestTask?.cancel()
        connectionTestTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let self, !Task.isCancelled else { return }
            await MainActor.run { self.testConnection() }
        }
    }

    private func testConnection() {
        guard canTestConnection else {
            connectionState = .unavailable
            refreshStatus()
            return
        }

        let settings = currentDraftSettings()
        connectionTestTask?.cancel()
        connectionTestTask =
        Task { [weak self] in
            guard let self else { return }
            let available = await LLMConnectionChecker(settings: settings).isAvailable()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.connectionState = available ? .available : .unavailable
                self.refreshStatus()
            }
        }
    }

    // MARK: - 模型列表

    @objc private func modelArrowClicked() {
        // 地址或 Key 为空时给短暂翻转反馈
        guard canTestConnection else {
            setArrowExpanded(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.setArrowExpanded(false)
            }
            return
        }

        setArrowExpanded(true)
        if availableModels.isEmpty {
            fetchModels()
        } else {
            showModelPicker()
            setArrowExpanded(false)
        }
    }

    private func setArrowExpanded(_ expanded: Bool) {
        let symbolName = expanded ? "chevron.up" : "chevron.down"
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        modelArrowButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    private func fetchModels() {
        guard canTestConnection else { return }

        let settings = currentDraftSettings()
        modelArrowButton.isEnabled = false

        guard let url = settings.modelsURL else {
            modelArrowButton.isEnabled = true
            setArrowExpanded(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(settings.effectiveAPIKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8

        Task { [weak self] in
            guard let self else { return }
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let response = try JSONDecoder().decode(ModelListResponse.self, from: data)
                await MainActor.run {
                    self.availableModels = response.data.map { $0.id }.sorted()
                    self.modelArrowButton.isEnabled = true
                    self.showModelPicker()
                    self.setArrowExpanded(false)
                }
            } catch {
                await MainActor.run {
                    self.modelArrowButton.isEnabled = true
                    self.setArrowExpanded(false)
                }
            }
        }
    }

    private func showModelPicker() {
        let menu = NSMenu()
        for model in availableModels {
            let item = NSMenuItem(title: model, action: #selector(modelSelected(_:)), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        if !availableModels.isEmpty {
            menu.addItem(.separator())
        }
        menu.addItem(NSMenuItem(title: "刷新列表", action: #selector(modelRefreshClicked), keyEquivalent: ""))
        let fieldRect = modelField.convert(modelField.bounds, to: nil)
        let screenRect = window?.convertToScreen(fieldRect) ?? .zero
        menu.popUp(positioning: nil, at: NSPoint(x: screenRect.minX, y: screenRect.minY), in: nil)
    }

    @objc private func modelSelected(_ sender: NSMenuItem) {
        modelField.stringValue = sender.title
        saveSettingsSoon()
    }

    @objc private func modelRefreshClicked() {
        fetchModels()
    }

    private struct ModelListResponse: Decodable {
        let data: [ModelEntry]
        struct ModelEntry: Decodable {
            let id: String
        }
    }

    @objc private func settingsDidChange() {
        refreshStatus()
    }

    @objc private func shortcutDidChange() {}

    @objc private func appDidBecomeActive() {
        refreshStatus()
    }

    func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSTextField {
            if field === apiKeyField {
                // 明文编辑时直接写入，密文时忽略（显示的是圆点不是真实值）
                if isApiKeyVisible {
                    apiKeyValue = apiKeyField.stringValue
                }
            }

            if field === apiEndpointField || field === apiKeyField {
                markUntested()
            }
        }
        saveSettingsSoon()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if obj.object as? NSTextField === apiKeyField {
            // 失焦前最后一次同步，防止极端情况下 apiKeyValue 未更新
            if isApiKeyVisible {
                apiKeyValue = apiKeyField.stringValue
            }
            if apiKeyAutoRevealed {
                apiKeyAutoRevealed = false
                isApiKeyVisible = false
                updateApiKeyDisplay()
                updateApiKeyEyeIcon()
            }
        }
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
