import AppKit
import CoreGraphics
import ServiceManagement

final class MainWindowController: NSObject, NSTextFieldDelegate {
    private static let apiDetailsExpandedKey = "ShotLens_API_DetailsExpanded"
    private static let lastAutomaticUpdateCheckKey = "ShotLens_LastAutomaticUpdateCheck"
    private var window: NSWindow?
    private var permissionStatusLabel: NSTextField?
    private var apiStatusLabel: NSTextField?
    private var updateStatusLabel: NSTextField?
    private var launchAtLoginSwitch: BlueSwitchControl?
    private let checkUpdateButton = NSButton()
    private let installUpdateButton = NSButton()
    private let toggleAPIButton = NSButton()
    private var apiDetailsContainer: NSStackView?
    private var isApiDetailsExpanded = UserDefaults.standard.bool(forKey: MainWindowController.apiDetailsExpandedKey)
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
        case transientFailure
        case unavailable
    }
    private var connectionState: ConnectionState = .untested
    private var connectionTestTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var automaticUpdateCheckTimer: Timer?
    private var availableUpdate: AppUpdate?
    private var didRunLaunchUpdateCheck = false

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
        automaticUpdateCheckTimer?.invalidate()
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
        scheduleAutomaticUpdateChecks()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        guard window?.isVisible == true else { return }
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 442),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ShotLens 控制台"
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 430, height: 442))
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
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -18)
        ])

        root.addArrangedSubview(makeHeader())
        root.addArrangedSubview(makePermissionCard())
        root.addArrangedSubview(makeShortcutCard())
        root.addArrangedSubview(makeStartupCard())
        root.addArrangedSubview(makeAPICard())
        root.addArrangedSubview(makeFooter())

        updateAPIExpandedState()
        updateWindowHeight(animated: false)
        window.center()
        return window
    }

    private func makeHeader() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.widthAnchor.constraint(equalToConstant: 398).isActive = true

        let icon = ShotLensGlyphIconView(frame: NSRect(x: 0, y: 0, width: 58, height: 58))
        icon.widthAnchor.constraint(equalToConstant: 58).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 58).isActive = true

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        textStack.addArrangedSubview(label("ShotLens", font: .systemFont(ofSize: 28, weight: .semibold)))
        textStack.addArrangedSubview(makeVersionRow())

        row.addArrangedSubview(icon)
        textStack.heightAnchor.constraint(equalToConstant: 58).isActive = true
        row.addArrangedSubview(textStack)
        return row
    }

    private func makeVersionRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6

        row.addArrangedSubview(label("版本 \(displayVersion)", font: .systemFont(ofSize: 13), color: .secondaryLabelColor))

        checkUpdateButton.title = "检测新版本"
        checkUpdateButton.bezelStyle = .inline
        checkUpdateButton.isBordered = true
        checkUpdateButton.toolTip = "检查新版本"
        checkUpdateButton.target = self
        checkUpdateButton.action = #selector(checkForUpdatesClicked)
        checkUpdateButton.translatesAutoresizingMaskIntoConstraints = false
        checkUpdateButton.widthAnchor.constraint(equalToConstant: 88).isActive = true
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
        textStack.spacing = 0
        textStack.addArrangedSubview(label("屏幕录制权限", font: .systemFont(ofSize: 14, weight: .medium)))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let status = label("", font: .systemFont(ofSize: 13, weight: .semibold))
        permissionStatusLabel = status

        let button = NSButton(title: "打开设置", target: self, action: #selector(openPermissionsClicked))
        button.bezelStyle = .rounded
        button.widthAnchor.constraint(equalToConstant: 96).isActive = true

        let rightControl = makeRightControlContainer(width: 180)
        let rightSpacer = NSView()
        rightSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rightControl.addArrangedSubview(rightSpacer)
        rightControl.addArrangedSubview(status)
        rightControl.addArrangedSubview(button)

        row.addArrangedSubview(textStack)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(rightControl)
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
        textStack.spacing = 0
        textStack.addArrangedSubview(label("开机自动启动", font: .systemFont(ofSize: 14, weight: .medium)))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let launchSwitch = BlueSwitchControl(frame: NSRect(x: 0, y: 0, width: 46, height: 26))
        launchSwitch.isOn = launchAtLoginEnabled
        launchSwitch.onChange = { [weak self] in
            self?.launchAtLoginChanged()
        }
        launchAtLoginSwitch = launchSwitch
        let rightControl = makeRightControlContainer(width: 180)
        let rightSpacer = NSView()
        rightSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rightControl.addArrangedSubview(rightSpacer)
        rightControl.addArrangedSubview(launchSwitch)

        row.addArrangedSubview(textStack)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(rightControl)
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
        textStack.spacing = 0
        textStack.addArrangedSubview(label("快捷键", font: .systemFont(ofSize: 14, weight: .medium)))

        let recorder = ShortcutRecorder(frame: NSRect(x: 0, y: 0, width: 180, height: 32))
        recorder.widthAnchor.constraint(equalToConstant: 180).isActive = true
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
        headerRow.widthAnchor.constraint(equalToConstant: 366).isActive = true

        headerRow.addArrangedSubview(label("API 信息", font: .systemFont(ofSize: 14, weight: .medium)))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerRow.addArrangedSubview(spacer)
        let status = label("", font: .systemFont(ofSize: 12, weight: .semibold), color: .secondaryLabelColor)
        apiStatusLabel = status
        headerRow.addArrangedSubview(status)
        toggleAPIButton.bezelStyle = .rounded
        toggleAPIButton.target = self
        toggleAPIButton.action = #selector(toggleAPIExpandedClicked)
        toggleAPIButton.widthAnchor.constraint(equalToConstant: 64).isActive = true
        headerRow.addArrangedSubview(toggleAPIButton)
        card.addArrangedSubview(headerRow)

        configureField(apiEndpointField, placeholder: "")
        configureField(modelField, placeholder: "")

        let details = NSStackView()
        details.orientation = .vertical
        details.alignment = .leading
        details.distribution = .fill
        details.spacing = 8
        details.widthAnchor.constraint(equalToConstant: 366).isActive = true
        apiDetailsContainer = details

        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 8
        actionRow.widthAnchor.constraint(equalToConstant: 366).isActive = true
        let actionSpacer = NSView()
        actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let clearButton = NSButton(title: "清空", target: self, action: #selector(clearAPISettingsClicked))
        clearButton.bezelStyle = .rounded
        clearButton.widthAnchor.constraint(equalToConstant: 58).isActive = true
        let testButton = NSButton(title: "测试", target: self, action: #selector(testConnectionClicked))
        testButton.bezelStyle = .rounded
        testButton.widthAnchor.constraint(equalToConstant: 58).isActive = true
        actionRow.addArrangedSubview(actionSpacer)
        actionRow.addArrangedSubview(clearButton)
        actionRow.addArrangedSubview(testButton)

        details.addArrangedSubview(fieldRow("地址", field: apiEndpointField))
        details.addArrangedSubview(apiKeyFieldRow())
        details.addArrangedSubview(modelFieldRow())
        details.addArrangedSubview(actionRow)

        card.addArrangedSubview(details)
        return card
    }

    private func makeFooter() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.widthAnchor.constraint(equalToConstant: 398).isActive = true

        let hint = label("设置会自动保存", font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let startButton = NSButton(title: "开始截图", target: self, action: #selector(startCaptureClicked))
        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"
        startButton.widthAnchor.constraint(equalToConstant: 116).isActive = true

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
        card.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.84).cgColor
        card.layer?.cornerRadius = 8
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.widthAnchor.constraint(equalToConstant: 398).isActive = true
        return card
    }

    private func makeRightControlContainer(width: CGFloat) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.widthAnchor.constraint(equalToConstant: width).isActive = true
        return row
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
        row.widthAnchor.constraint(equalToConstant: 366).isActive = true

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

        // 外层容器 318×28
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalToConstant: 318).isActive = true
        container.heightAnchor.constraint(equalToConstant: 28).isActive = true

        // 文本框 290，眼图标间距 6
        container.addSubview(apiKeyField)
        NSLayoutConstraint.activate([
            apiKeyField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            apiKeyField.widthAnchor.constraint(equalToConstant: 290),
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
        row.widthAnchor.constraint(equalToConstant: 366).isActive = true

        let titleLabel = label("模型", font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        titleLabel.widthAnchor.constraint(equalToConstant: 38).isActive = true

        // 外层容器 318×28
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalToConstant: 318).isActive = true
        container.heightAnchor.constraint(equalToConstant: 28).isActive = true

        // 文本框 290，箭头在右侧间距 6
        modelField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(modelField)
        NSLayoutConstraint.activate([
            modelField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            modelField.widthAnchor.constraint(equalToConstant: 290),
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
        row.widthAnchor.constraint(equalToConstant: 366).isActive = true

        let titleLabel = label(title, font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        titleLabel.widthAnchor.constraint(equalToConstant: 38).isActive = true
        field.widthAnchor.constraint(equalToConstant: 318).isActive = true

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

    private func updateAPIExpandedState() {
        apiDetailsContainer?.isHidden = !isApiDetailsExpanded
        toggleAPIButton.title = isApiDetailsExpanded ? "收起" : "展开"
    }

    private func updateWindowHeight(animated: Bool) {
        guard let window else { return }
        let targetHeight: CGFloat = isApiDetailsExpanded ? 526 : 404
        var frame = window.frame
        guard abs(frame.height - targetHeight) > 0.5 else { return }
        frame.origin.y += frame.height - targetHeight
        frame.size.height = targetHeight
        window.setFrame(frame, display: true, animate: animated)
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
        if !settings.isLLMConfigured {
            isApiDetailsExpanded = true
        }
        isApiKeyVisible = false
        apiKeyAutoRevealed = false
        updateApiKeyDisplay()
        updateApiKeyEyeIcon()
        modelField.stringValue = settings.model
        launchAtLoginSwitch?.isOn = launchAtLoginEnabled

        // 不自动测试，等用户手动点击「测试」按钮
        connectionState = .untested
        updateAPIExpandedState()
        updateWindowHeight(animated: false)
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
            apiStatusLabel?.stringValue = "● 未配置"
            apiStatusLabel?.textColor = .secondaryLabelColor
        case .untested:
            let settings = currentDraftSettings()
            if !settings.isLLMConfigured {
                apiStatusLabel?.stringValue = "● 未配置"
            } else {
                apiStatusLabel?.stringValue = "● 自定义 API"
            }
            apiStatusLabel?.textColor = .secondaryLabelColor
        case .testing:
            apiStatusLabel?.stringValue = "● 测试中…"
            apiStatusLabel?.textColor = .secondaryLabelColor
        case .available:
            apiStatusLabel?.stringValue = "● 可用"
            apiStatusLabel?.textColor = .systemGreen
        case .transientFailure:
            apiStatusLabel?.stringValue = "● 暂时不可用"
            apiStatusLabel?.textColor = .systemOrange
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
        let shouldEnable = launchAtLoginSwitch?.isOn == true
        do {
            if shouldEnable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginSwitch?.isOn = launchAtLoginEnabled
            ShotLensLogger.log("更新开机自动启动失败", error: error)
        }
    }

    @objc private func testConnectionClicked() {
        connectionTestTask?.cancel()
        syncAPIKeyDraftFromField()
        flushPendingSave()
        // 先无条件显示"测试中…"，让用户感知按钮已被触发
        connectionState = .testing
        refreshStatus()
        testConnection()
    }

    @objc private func clearAPISettingsClicked() {
        pendingSave?.cancel()
        TranslationSettings.clearSavedConfiguration()
        connectionState = .untested
        availableModels = []
        apiKeyValue = ""
        isApiKeyVisible = false
        apiKeyAutoRevealed = false
        loadSettings()
        refreshStatus()
    }

    @objc private func toggleAPIExpandedClicked() {
        isApiDetailsExpanded.toggle()
        UserDefaults.standard.set(isApiDetailsExpanded, forKey: Self.apiDetailsExpandedKey)
        updateAPIExpandedState()
        refreshStatus()
        updateWindowHeight(animated: true)
    }

    // MARK: - 更新检查

    @objc private func checkForUpdatesClicked() {
        startUpdateCheck(showsProgress: true, automaticallyInstalls: false)
    }

    private func startUpdateCheck(showsProgress: Bool, automaticallyInstalls: Bool) {
        updateTask?.cancel()
        availableUpdate = nil
        installUpdateButton.isHidden = true
        if showsProgress {
            checkUpdateButton.isEnabled = false
            checkUpdateButton.title = "检测中…"
            updateStatusLabel?.stringValue = "检查中…"
            updateStatusLabel?.textColor = .secondaryLabelColor
        }

        updateTask = Task { [weak self] in
            let result = await AppUpdater().checkForUpdate()
            guard !Task.isCancelled, let controller = self else { return }
            await MainActor.run {
                controller.applyUpdateCheckResult(
                    result,
                    showsProgress: showsProgress,
                    automaticallyInstalls: automaticallyInstalls
                )
            }
        }
    }

    private func applyUpdateCheckResult(
        _ result: AppUpdateCheckResult,
        showsProgress: Bool,
        automaticallyInstalls: Bool
    ) {
        updateTask = nil
        if showsProgress {
            checkUpdateButton.isEnabled = true
            checkUpdateButton.title = "检测新版本"
        }
        switch result {
        case .available(let update):
            availableUpdate = update
            updateStatusLabel?.stringValue = "发现 \(update.version)"
            updateStatusLabel?.textColor = .systemGreen
            installUpdateButton.isHidden = false
            if automaticallyInstalls, AppUpdater.canAutomaticallyInstall() {
                beginInstalling(update)
            }
        case .upToDate:
            guard showsProgress else { return }
            availableUpdate = nil
            updateStatusLabel?.stringValue = "已是最新版"
            updateStatusLabel?.textColor = .secondaryLabelColor
            installUpdateButton.isHidden = true
        case .failed:
            guard showsProgress else { return }
            availableUpdate = nil
            updateStatusLabel?.stringValue = "无法连接更新服务器"
            updateStatusLabel?.textColor = .systemOrange
            installUpdateButton.isHidden = true
        }
    }

    private func scheduleAutomaticUpdateChecks() {
        if !didRunLaunchUpdateCheck {
            didRunLaunchUpdateCheck = true
            UserDefaults.standard.set(Date(), forKey: Self.lastAutomaticUpdateCheckKey)
            startUpdateCheck(showsProgress: false, automaticallyInstalls: true)
        }
        guard automaticUpdateCheckTimer == nil else { return }
        automaticUpdateCheckTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            self?.performAutomaticUpdateCheckIfNeeded()
        }
    }

    private func performAutomaticUpdateCheckIfNeeded() {
        guard updateTask == nil, availableUpdate == nil else { return }
        let defaults = UserDefaults.standard
        let lastCheckedAt = defaults.object(forKey: Self.lastAutomaticUpdateCheckKey) as? Date
        let now = Date()
        guard AppUpdater.shouldAutomaticallyCheck(lastCheckedAt: lastCheckedAt, now: now) else { return }
        defaults.set(now, forKey: Self.lastAutomaticUpdateCheckKey)
        startUpdateCheck(showsProgress: false, automaticallyInstalls: false)
    }

    @objc private func installUpdateClicked() {
        guard let update = availableUpdate else { return }
        beginInstalling(update)
    }

    private func beginInstalling(_ update: AppUpdate) {
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
                        controller.updateStatusLabel?.stringValue = "安装中…"
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
        checkUpdateButton.title = "检测新版本"
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
        syncAPIKeyDraftFromField()
        guard canTestConnection else {
            connectionState = .notConfigured
            refreshStatus()
            return
        }

        let settings = currentDraftSettings()
        connectionTestTask?.cancel()
        connectionTestTask =
        Task { [weak self] in
            guard let self else { return }
            let result = await LLMConnectionChecker(settings: settings).checkAvailability()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                switch result {
                case .available:
                    self.connectionState = .available
                case .transientFailure:
                    self.connectionState = .transientFailure
                case .unavailable:
                    self.connectionState = .unavailable
                }
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
        performAutomaticUpdateCheckIfNeeded()
    }

    func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSTextField {
            if field === apiKeyField {
                // 明文编辑时直接写入，密文时忽略（显示的是圆点不是真实值）
                syncAPIKeyDraftFromField()
            }

            if field === apiEndpointField || field === apiKeyField || field === modelField {
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

    private func syncAPIKeyDraftFromField() {
        guard isApiKeyVisible else { return }
        apiKeyValue = apiKeyField.stringValue
    }
}

private final class BlueSwitchControl: NSControl {
    var onChange: (() -> Void)?

    var isOn = false {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 46, height: 26)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "开机自动启动"
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        let trackRect = bounds.insetBy(dx: 1, dy: 1)
        let trackColor = isOn
            ? NSColor.systemBlue
            : NSColor.tertiaryLabelColor.withAlphaComponent(0.28)
        trackColor.setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: trackRect.height / 2, yRadius: trackRect.height / 2).fill()

        if !isOn {
            NSColor.separatorColor.withAlphaComponent(0.65).setStroke()
            let border = NSBezierPath(roundedRect: trackRect, xRadius: trackRect.height / 2, yRadius: trackRect.height / 2)
            border.lineWidth = 1
            border.stroke()
        }

        let knobSize: CGFloat = 20
        let knobX = isOn ? bounds.maxX - knobSize - 4 : bounds.minX + 4
        let knobRect = CGRect(x: knobX, y: bounds.midY - knobSize / 2, width: knobSize, height: knobSize)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knobRect).fill()
    }

    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
        onChange?()
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
