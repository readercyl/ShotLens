import AppKit
import CoreGraphics
import ServiceManagement

final class MainWindowController: NSObject, NSTextFieldDelegate {
    private static let apiDetailsExpandedKey = "ShotLens_API_DetailsExpanded"
    private static let lastAutomaticUpdateCheckKey = "ShotLens_LastAutomaticUpdateCheck"
    private var window: NSWindow?
    private var permissionStatusLabel: NSTextField?
    private var apiStatusLabel: NSTextField?
    private var apiStatusDetailLabel: NSTextField?
    private var updateStatusLabel: NSTextField?
    private var pipelineMessageContainer: NSStackView?
    private var pipelineMessageTitleLabel: NSTextField?
    private var pipelineMessageDetailLabel: NSTextField?
    private var diagnosticsStatusLabel: NSTextField?
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
    private var connectionDetailText: String?
    private var connectionTestTask: Task<Void, Never>?
    private var modelFetchTask: Task<Void, Never>?
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
        let pipelineMessage = makePipelineMessage()
        pipelineMessage.isHidden = true
        pipelineMessageContainer = pipelineMessage
        root.addArrangedSubview(pipelineMessage)
        root.addArrangedSubview(makePermissionCard())
        root.addArrangedSubview(makeShortcutCard())
        root.addArrangedSubview(makeStartupCard())
        root.addArrangedSubview(makeAPICard())
        root.addArrangedSubview(makeDiagnosticsCard())
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

        let statusDetail = label("", font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        statusDetail.lineBreakMode = .byWordWrapping
        statusDetail.maximumNumberOfLines = 2
        statusDetail.preferredMaxLayoutWidth = 366
        statusDetail.widthAnchor.constraint(equalToConstant: 366).isActive = true
        statusDetail.isHidden = true
        apiStatusDetailLabel = statusDetail
        card.addArrangedSubview(statusDetail)

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

    private func makePipelineMessage() -> NSStackView {
        let container = makeCard()
        container.spacing = 3
        container.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        container.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.08).cgColor
        container.layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.28).cgColor

        let title = label("", font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor)
        let detail = label("", font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        detail.lineBreakMode = .byWordWrapping
        detail.maximumNumberOfLines = 2
        detail.preferredMaxLayoutWidth = 374
        title.widthAnchor.constraint(equalToConstant: 374).isActive = true
        detail.widthAnchor.constraint(equalToConstant: 374).isActive = true
        pipelineMessageTitleLabel = title
        pipelineMessageDetailLabel = detail
        container.addArrangedSubview(title)
        container.addArrangedSubview(detail)
        return container
    }

    private func makeDiagnosticsCard() -> NSView {
        let card = makeCard()
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.widthAnchor.constraint(equalToConstant: 366).isActive = true

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.addArrangedSubview(label("诊断日志", font: .systemFont(ofSize: 14, weight: .medium)))
        let status = label("不保存截图、原文或译文", font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        diagnosticsStatusLabel = status
        textStack.addArrangedSubview(status)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let copyButton = NSButton(title: "复制诊断", target: self, action: #selector(copyDiagnosticsClicked))
        copyButton.bezelStyle = .rounded
        copyButton.widthAnchor.constraint(equalToConstant: 76).isActive = true
        let openButton = NSButton(title: "打开日志", target: self, action: #selector(openDiagnosticsClicked))
        openButton.bezelStyle = .rounded
        openButton.widthAnchor.constraint(equalToConstant: 76).isActive = true
        let clearButton = NSButton(title: "清空", target: self, action: #selector(clearDiagnosticsClicked))
        clearButton.bezelStyle = .rounded
        clearButton.widthAnchor.constraint(equalToConstant: 58).isActive = true

        row.addArrangedSubview(textStack)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(copyButton)
        row.addArrangedSubview(openButton)
        row.addArrangedSubview(clearButton)
        card.addArrangedSubview(row)
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

        // 文本框 284，图标点击区 28，间距 6
        container.addSubview(apiKeyField)
        NSLayoutConstraint.activate([
            apiKeyField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            apiKeyField.widthAnchor.constraint(equalToConstant: 284),
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
            apiKeyEyeButton.widthAnchor.constraint(equalToConstant: 28),
            apiKeyEyeButton.heightAnchor.constraint(equalToConstant: 28),
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
        let label = isApiKeyVisible ? "隐藏 API Key" : "显示 API Key"
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        apiKeyEyeButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)?.withSymbolConfiguration(config)
        apiKeyEyeButton.toolTip = label
        apiKeyEyeButton.setAccessibilityLabel(label)
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

        // 文本框 284，箭头点击区 28，间距 6
        modelField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(modelField)
        NSLayoutConstraint.activate([
            modelField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            modelField.widthAnchor.constraint(equalToConstant: 284),
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
            modelArrowButton.widthAnchor.constraint(equalToConstant: 28),
            modelArrowButton.heightAnchor.constraint(equalToConstant: 28),
            modelArrowButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        setArrowExpanded(false)

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
        let baseHeight: CGFloat = isApiDetailsExpanded ? 586 : 464
        let pipelineHeight: CGFloat = pipelineMessageContainer?.isHidden == false ? 62 : 0
        let apiDetailHeight: CGFloat = apiStatusDetailLabel?.isHidden == false ? 30 : 0
        let targetHeight = baseHeight + pipelineHeight + apiDetailHeight
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
        connectionDetailText = nil
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
        apiStatusDetailLabel?.stringValue = connectionDetailText ?? ""
        apiStatusDetailLabel?.isHidden = connectionDetailText?.isEmpty != false
        updateWindowHeight(animated: false)
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
            if !self.currentDraftSettings().save() {
                self.showPipelineMessage("无法保存 API Key", detail: "钥匙串写入失败，原有 Key 未被覆盖。")
            }
            self.refreshStatus()
        }
        pendingSave = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    @objc private func startCaptureClicked() {
        hidePipelineMessage()
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
            ShotLensLogger.event("launch_at_login_update_failed", level: .error, stage: "settings", outcome: "failed", error: error)
            showPipelineMessage("无法更新开机启动", detail: "系统没有接受此设置，请稍后再试。")
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
        connectionTestTask?.cancel()
        connectionTestTask = nil
        modelFetchTask?.cancel()
        modelFetchTask = nil
        if !TranslationSettings.clearSavedConfiguration() {
            showPipelineMessage("无法清空 API Key", detail: "钥匙串没有接受删除请求，请稍后再试。")
        }
        connectionState = .untested
        connectionDetailText = nil
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
        case .failed(let message):
            guard showsProgress else { return }
            availableUpdate = nil
            updateStatusLabel?.stringValue = message
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
                        controller.showUpdateInstallFailure(reason: "无法启动安装程序")
                    }
                }
            } catch {
                guard let controller = self else { return }
                await MainActor.run {
                    let reason = (error as? AppUpdaterError)?.errorDescription ?? "下载连接中断"
                    controller.showUpdateInstallFailure(reason: reason)
                }
            }
        }
    }

    private func showUpdateInstallFailure(reason: String) {
        checkUpdateButton.isEnabled = true
        installUpdateButton.isEnabled = true
        checkUpdateButton.title = "检测新版本"
        updateStatusLabel?.stringValue = "升级失败：\(reason)"
        updateStatusLabel?.textColor = .systemRed
        ShotLensLogger.event("update_install_failed", level: .error, stage: "update", outcome: "failed")
    }

    private func markUntested() {
        connectionTestTask?.cancel()
        connectionTestTask = nil
        modelFetchTask?.cancel()
        modelFetchTask = nil
        modelArrowButton.isEnabled = true
        setArrowExpanded(false)
        connectionState = .untested
        connectionDetailText = nil
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
            ShotLensLogger.event("api_connection_test_started", stage: "connection_test")
            let report = await LLMConnectionChecker(settings: settings).checkReport()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.currentDraftSettings() == settings else { return }
                switch report.result {
                case .available:
                    self.connectionState = .available
                    self.connectionDetailText = nil
                case .transientFailure:
                    self.connectionState = .transientFailure
                case .unavailable:
                    self.connectionState = .unavailable
                }
                if let kind = report.failureKind {
                    let failure = PipelineFailurePresentation.make(kind: kind)
                    self.connectionDetailText = "\(failure.title)：\(failure.detail)"
                }
                self.connectionTestTask = nil
                self.refreshStatus()
            }
        }
    }

    // MARK: - 模型列表

    @objc private func modelArrowClicked() {
        // 地址或 Key 为空时给短暂翻转反馈
        guard canTestConnection else {
            connectionState = .notConfigured
            connectionDetailText = "请先填写 API 地址和 Key。"
            refreshStatus()
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
        let label = expanded ? "收起模型列表" : "打开模型列表"
        modelArrowButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)?.withSymbolConfiguration(config)
        modelArrowButton.toolTip = label
        modelArrowButton.setAccessibilityLabel(label)
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
        let host = url.host?.lowercased() ?? ""
        if host == "api.xiaomimimo.com" || host.hasSuffix(".xiaomimimo.com") {
            request.setValue(settings.effectiveAPIKey, forHTTPHeaderField: "api-key")
        }

        modelFetchTask?.cancel()
        modelFetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw ModelListFetchError.httpStatus(http.statusCode)
                }
                let modelResponse = try JSONDecoder().decode(ModelListResponse.self, from: data)
                await MainActor.run {
                    guard !Task.isCancelled, self.currentDraftSettings() == settings else { return }
                    self.availableModels = modelResponse.data.map { $0.id }.sorted()
                    self.modelArrowButton.isEnabled = true
                    self.modelFetchTask = nil
                    self.connectionDetailText = self.availableModels.isEmpty
                        ? "服务没有返回可选模型，可以直接手动填写模型名称。"
                        : nil
                    self.refreshStatus()
                    self.showModelPicker()
                    self.setArrowExpanded(false)
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled, self.currentDraftSettings() == settings else { return }
                    self.modelArrowButton.isEnabled = true
                    self.modelFetchTask = nil
                    self.connectionDetailText = self.modelListFailureMessage(for: error)
                    self.refreshStatus()
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

    private func modelListFailureMessage(for error: Error) -> String {
        if let modelError = error as? ModelListFetchError,
           case .httpStatus(let statusCode) = modelError {
            if statusCode == 401 || statusCode == 403 {
                return "模型列表验证失败，请检查 Key 或服务权限。"
            }
            if statusCode == 404 {
                return "服务不提供模型列表，可以直接手动填写模型名称。"
            }
            if statusCode == 429 {
                return "模型列表请求过多，请稍后再试。"
            }
            return "模型列表请求失败（HTTP \(statusCode)）。"
        }
        if let urlError = error as? URLError {
            return urlError.code == .timedOut
                ? "获取模型列表超时，可以直接手动填写模型名称。"
                : "无法连接模型列表，可以直接手动填写模型名称。"
        }
        return "模型列表返回格式无效，可以直接手动填写模型名称。"
    }

    func showPipelineFailure(_ failure: PipelineFailurePresentation) {
        showPipelineMessage(failure.title, detail: failure.detail)
    }

    func showPipelineMessage(_ title: String, detail: String) {
        pipelineMessageTitleLabel?.stringValue = title
        pipelineMessageDetailLabel?.stringValue = detail
        pipelineMessageContainer?.isHidden = false
        updateWindowHeight(animated: true)
    }

    private func hidePipelineMessage() {
        guard pipelineMessageContainer?.isHidden == false else { return }
        pipelineMessageContainer?.isHidden = true
        updateWindowHeight(animated: true)
    }

    @objc private func copyDiagnosticsClicked() {
        guard let text = ShotLensLogger.latestDiagnosticText(), !text.isEmpty else {
            diagnosticsStatusLabel?.stringValue = "暂无诊断记录"
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        diagnosticsStatusLabel?.stringValue = "已复制最近诊断"
    }

    @objc private func openDiagnosticsClicked() {
        do {
            try ShotLensLogger.ensureDiagnosticDirectory()
            NSWorkspace.shared.open(ShotLensLogger.diagnosticDirectoryURL)
            diagnosticsStatusLabel?.stringValue = "已打开日志文件夹"
        } catch {
            diagnosticsStatusLabel?.stringValue = "无法打开日志文件夹"
        }
    }

    @objc private func clearDiagnosticsClicked() {
        do {
            try ShotLensLogger.clearDiagnostics()
            diagnosticsStatusLabel?.stringValue = "日志已清空"
        } catch {
            diagnosticsStatusLabel?.stringValue = "无法清空日志"
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
        if !currentDraftSettings().save() {
            showPipelineMessage("无法保存 API Key", detail: "钥匙串写入失败，原有 Key 未被覆盖。")
        }
        refreshStatus()
    }

    private func syncAPIKeyDraftFromField() {
        guard isApiKeyVisible else { return }
        apiKeyValue = apiKeyField.stringValue
    }
}

private enum ModelListFetchError: Error, ShotLensDiagnosticError {
    case httpStatus(Int)

    var diagnosticCode: String { "models.http_error" }

    var diagnosticMetadata: [String: String] {
        switch self {
        case .httpStatus(let statusCode):
            return ["http_status": String(statusCode)]
        }
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
