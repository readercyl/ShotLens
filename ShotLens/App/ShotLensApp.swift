import AppKit
import Carbon

/// 瞬译应用入口。双击启动后显示主窗口，同时保留菜单栏和全局快捷键。
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: AppDelegate?
    private static let legacyDefaultsSuiteName = "com.qingcheng.shotlens"
    private static let legacyDefaultsMigrationKey = "ShotLens_DidMigrateLegacyDefaults"

    private var statusItem: NSStatusItem?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private var hotKeyID = EventHotKeyID(signature: 0x53484F54, id: 1) // "SHOT"
    private let mainWindowController = MainWindowController()
    private var resultOverlay: OverlayWindow?
    private var activeSelectionOverlay: InProcessSelectionOverlay?
    private var isProcessing = false
    private var isRecordingShortcut = false
    /// 弱引用 self 供 C 回调使用
    private static var shared: AppDelegate?

    static func main() {
        migrateLegacyDefaultsIfNeeded()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.run()
    }

    private static func migrateLegacyDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: legacyDefaultsMigrationKey),
              let legacyDefaults = UserDefaults(suiteName: legacyDefaultsSuiteName) else { return }

        for (key, value) in legacyDefaults.dictionaryRepresentation()
            where key.hasPrefix("ShotLens_") && defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: legacyDefaultsMigrationKey)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        ProcessInfo.processInfo.disableAutomaticTermination("ShotLens stays active for menu bar capture")
        NSApp.setActivationPolicy(.regular)
        setupMainMenu()
        setupMenuBar()
        installHotKeyHandler()
        registerGlobalHotKey()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotKeyDidChange),
            name: ShortcutRecorder.hotKeyChangedNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotKeyRecordingDidBegin),
            name: ShortcutRecorder.recordingDidBeginNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotKeyRecordingDidEnd),
            name: ShortcutRecorder.recordingDidEndNotification,
            object: nil
        )

        openMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return true
    }

    @objc private func hotKeyDidChange() {
        guard !isRecordingShortcut else { return }
        unregisterGlobalHotKey()
        registerGlobalHotKey()
    }

    @objc private func hotKeyRecordingDidBegin() {
        isRecordingShortcut = true
        unregisterGlobalHotKey()
    }

    @objc private func hotKeyRecordingDidEnd() {
        isRecordingShortcut = false
        unregisterGlobalHotKey()
        registerGlobalHotKey()
    }

    func openPreferences() {
        openMainWindow()
    }

    func openMainWindow() {
        mainWindowController.show(
            onStartCapture: { [weak self] in
                self?.startCapture()
            },
            onOpenPermissions: { [weak self] in
                self?.openScreenCapturePrivacySettings()
            }
        )
    }

    func startCapture() {
        handleHotKey()
    }

    // MARK: - 主菜单

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu

        // ── 应用菜单 ──
        let appMenu = NSMenu()
        let appMenuItem = mainMenu.addItem(withTitle: "ShotLens", action: nil, keyEquivalent: "")
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 ShotLens", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 ShotLens", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // ── 编辑菜单（Cmd+V/Cmd+C/Cmd+X 依赖这个）──
        let editMenu = NSMenu(title: "编辑")
        let editMenuItem = mainMenu.addItem(withTitle: "编辑", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    }

    // MARK: - 菜单栏

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = true

        if let button = item.button {
            button.image = makeMenuBarTemplateIcon()
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = "瞬译"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "显示主窗口",
            action: #selector(showMainWindowMenuItem),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "开始截图",
            action: #selector(startCaptureFromMenu),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "打开控制台",
            action: #selector(openPreferencesMenuItem),
            keyEquivalent: ","
        ))
        menu.addItem(NSMenuItem(
            title: "打开屏幕录制权限",
            action: #selector(openPermissionsMenuItem),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "退出瞬译",
            action: #selector(quitApp),
            keyEquivalent: "q"
        ))
        item.menu = menu
        statusItem = item
    }

    private func makeMenuBarTemplateIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        if let image = NSImage(named: "ShotLensMenuBarTemplate") {
            image.size = size
            image.isTemplate = true
            image.accessibilityDescription = "ShotLens"
            return image
        }

        let image = NSImage(size: size)
        image.lockFocus()

        let text = "译" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14.5, weight: .black),
            .foregroundColor: NSColor.black
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            in: NSRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2 + 0.5,
                width: textSize.width,
                height: textSize.height
            ),
            withAttributes: attributes
        )

        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "ShotLens"
        return image
    }

    @objc private func openPreferencesMenuItem() {
        openPreferences()
    }

    @objc private func openPermissionsMenuItem() {
        openScreenCapturePrivacySettings()
    }

    @objc private func showMainWindowMenuItem() {
        openMainWindow()
    }

    @objc private func startCaptureFromMenu() {
        startCapture()
    }

    @objc private func quitApp() {
        unregisterGlobalHotKey()
        uninstallHotKeyHandler()
        NSApp.terminate(nil)
    }

    // MARK: - 全局快捷键

    private func installHotKeyHandler() {
        guard hotKeyHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, event, _) -> OSStatus in
                var eventHotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &eventHotKeyID
                )

                guard eventHotKeyID.signature == 0x53484F54 else {
                    return noErr
                }

                Task { @MainActor in
                    AppDelegate.shared?.handleHotKey()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &hotKeyHandlerRef
        )

        if status != noErr {
            NSLog("[ShotLens] InstallEventHandler 失败: %d", Int(status))
        }
    }

    private func registerGlobalHotKey() {
        guard hotKeyRef == nil else { return }
        guard hotKeyHandlerRef != nil else {
            NSLog("[ShotLens] 热键事件处理器未安装")
            return
        }

        let hotKey = HotKey.loadSavedOrDefault()

        NSLog("[ShotLens] 注册快捷键 keyCode=%d modifiers=0x%X (%@)",
              hotKey.keyCode, hotKey.modifiers, hotKey.displayString)

        let status = RegisterEventHotKey(
            UInt32(hotKey.keyCode),
            UInt32(hotKey.modifiers),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            NSLog("[ShotLens] RegisterEventHotKey 失败: %d", Int(status))
            return
        }

        NSLog("[ShotLens] RegisterEventHotKey 成功")
    }

    private func unregisterGlobalHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
            NSLog("[ShotLens] 已注销旧快捷键")
        }
    }

    private func uninstallHotKeyHandler() {
        if let ref = hotKeyHandlerRef {
            RemoveEventHandler(ref)
            hotKeyHandlerRef = nil
        }
    }

    // MARK: - 主流程

    private func handleHotKey() {
        guard !isProcessing else { return }
        isProcessing = true
        ShotLensLogger.log("快捷键触发")

        // 确保最新设置已写入 UserDefaults，翻译链路才能读到
        mainWindowController.flushPendingSave()

        Task {
            await executeTranslationFlow()
            isProcessing = false
        }
    }

    private func executeTranslationFlow() async {
        // 从文本框直接抓设置，不依赖 UserDefaults 时序
        let translationSettings = await MainActor.run { mainWindowController.currentDraftSettings() }

        guard translationSettings.isLLMConfigured else {
            ShotLensLogger.log("自定义 API 未配置，停止截图翻译")
            await MainActor.run { openMainWindow() }
            return
        }

        let capture = ScreenshotCapture()
        let targetMouseLocation = NSEvent.mouseLocation

        guard capture.hasScreenCaptureAccess() else {
            ShotLensLogger.log("屏幕录制权限未开启，无法冻结屏幕")
            openMainWindow()
            return
        }

        await MainActor.run {
            mainWindowController.hide()
        }

        let frozenSnapshot: FrozenScreenshot
        do {
            guard let snapshot = try await capture.captureFrozenDisplay(containing: targetMouseLocation) else {
                ShotLensLogger.log("冻结屏幕失败，未生成截图文件")
                return
            }
            frozenSnapshot = snapshot
        } catch {
            ShotLensLogger.log("冻结屏幕失败", error: error)
            return
        }

        let selection: CGRect?
        let selectionOverlay = InProcessSelectionOverlay()
        activeSelectionOverlay = selectionOverlay
        selection = await selectionOverlay.select(frozenScreenshot: frozenSnapshot)
        activeSelectionOverlay = nil

        guard let selection else {
            ShotLensLogger.log("用户取消截图")
            return
        }
        ShotLensLogger.log("选区完成 x=\(selection.minX) y=\(selection.minY) width=\(selection.width) height=\(selection.height)")

        let captureSelection = SelectionGeometry.expandedRect(
            for: selection,
            within: frozenSnapshot.screenRect
        )
        let ocrCapture: CapturedScreenshot?
        do {
            ocrCapture = try capture.crop(
                frozenSnapshot: frozenSnapshot,
                selection: captureSelection,
                userSelection: selection
            )
        } catch {
            ShotLensLogger.log("冻结截图裁剪失败", error: error)
            return
        }

        guard let ocrCapture else {
            ShotLensLogger.log("冻结截图裁剪为空")
            return
        }

        let displayCapture: CapturedScreenshot?
        do {
            displayCapture = try capture.crop(
                frozenSnapshot: frozenSnapshot,
                selection: selection
            )
        } catch {
            displayCapture = nil
            ShotLensLogger.log("原始框选截图裁剪失败", error: error)
        }
        guard let displayCapture else {
            ShotLensLogger.log("原始框选截图裁剪为空")
            return
        }
        await MainActor.run {
            ClipboardManager().copyImageToClipboard(image: displayCapture.image)
        }
        ShotLensLogger.log("原始框选截图已保存到剪贴板")

        let displayScale = SelectionGeometry.displayScale(
            forPixelSize: CGSize(width: displayCapture.image.width, height: displayCapture.image.height),
            captureRect: selection
        )

        await showInteractiveOverlay(
            ocrCapture: ocrCapture,
            displayImage: displayCapture.image,
            selection: selection,
            displayScale: displayScale,
            translationSettings: translationSettings
        )
    }

    private func openScreenCapturePrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func translate(
        captured: CapturedScreenshot,
        displayPixelSize: CGSize,
        overlay: OverlayWindow?,
        settings: TranslationSettings
    ) async {
        let pipelineStartedAt = Date()
        overlay?.setProcessing("正在识别文字...")

        let ocr = OCREngine()
        let ocrStartedAt = Date()
        let textBlocks: [TextBlock]
        do {
            textBlocks = try await ocr.recognize(imageFile: captured.fileURL)
        } catch {
            ShotLensLogger.log("OCR 失败", error: error)
            overlay?.setMessage("识别失败")
            return
        }

        let selectedTextBlocks = textBlocks.filter {
            SelectionGeometry.shouldInclude($0.boundingBox, in: captured.userSelectionRectInImage)
        }
        guard !selectedTextBlocks.isEmpty else {
            ShotLensLogger.log("未识别到文字")
            overlay?.setMessage("未识别到文字")
            return
        }
        let displayTextBlocks = selectedTextBlocks.compactMap {
            SelectionGeometry.mapOCRBlockToDisplay(
                $0,
                userSelectionRectInOCR: captured.userSelectionRectInImage,
                displayPixelSize: displayPixelSize
            )
        }
        ShotLensLogger.log(String(format: "OCR 完成，识别 %d 个文本块，选区内 %d 个，显示坐标 %d 个，耗时 %.2fs", textBlocks.count, selectedTextBlocks.count, displayTextBlocks.count, Date().timeIntervalSince(ocrStartedAt)))
        let semanticBlocks = SemanticTextGrouper.merge(displayTextBlocks)
        ShotLensLogger.log("语义分组完成，\(displayTextBlocks.count) 个 OCR 行合并为 \(semanticBlocks.count) 个文本块")
        let contentPlan = TranslationContentPlan.make(from: semanticBlocks)
        guard !contentPlan.sourceTexts.isEmpty else {
            ShotLensLogger.log("选区内没有需要翻译的英文")
            overlay?.setMessage("未识别到英文")
            return
        }

        configureTranslationRetry(
            contentPlan,
            overlay: overlay,
            settings: settings
        )
        await translateRecognized(contentPlan, overlay: overlay, settings: settings, pipelineStartedAt: pipelineStartedAt)
    }

    private func configureTranslationRetry(
        _ contentPlan: TranslationContentPlan,
        overlay: OverlayWindow?,
        settings: TranslationSettings
    ) {
        let retry = { [weak self, weak overlay] in
            guard let self else { return }
            ShotLensLogger.log("复用 OCR 结果重新翻译")
            Task {
                await self.translateRecognized(
                    contentPlan,
                    overlay: overlay,
                    settings: settings,
                    pipelineStartedAt: Date()
                )
            }
        }
        overlay?.onRetry = retry
        overlay?.onRetranslate = retry
    }

    private func translateRecognized(
        _ contentPlan: TranslationContentPlan,
        overlay: OverlayWindow?,
        settings: TranslationSettings,
        pipelineStartedAt: Date
    ) async {

        overlay?.setProcessing("正在翻译...")

        // 2. 确定源语言和目标语言
        let sourceLang = "auto"
        let targetLang = "zh-Hans"

        let provider = TranslationProviderFactory.create(with: settings)
        let texts = contentPlan.sourceTexts
        let translationStartedAt = Date()
        let translationResult: TranslationBatchResult
        do {
            translationResult = try await provider.translateAvailable(
                texts,
                from: sourceLang,
                to: targetLang
            )
        } catch {
            ShotLensLogger.log("翻译失败", error: error)
            overlay?.setMessage(userFacingTranslationFailureMessage(for: error))
            return
        }
        guard translationResult.isComplete,
              let translatedBlocks = contentPlan.applyingAvailable(translationResult.translations),
              !translatedBlocks.isEmpty else {
            ShotLensLogger.log("翻译返回数量与待翻译英文片段不一致")
            overlay?.setMessage("翻译失败：部分内容未完成")
            return
        }
        ShotLensLogger.log(String(
            format: "翻译完成，使用 %@，完成 %d/%d 个英文片段，耗时 %.2fs",
            provider.name,
            translationResult.completedCount,
            translationResult.translations.count,
            Date().timeIntervalSince(translationStartedAt)
        ))

        overlay?.setTranslatedBlocks(translatedBlocks, isPartial: !translationResult.isComplete)
        ShotLensLogger.log(String(format: "翻译流程总耗时 %.2fs", Date().timeIntervalSince(pipelineStartedAt)))
    }

    private func userFacingTranslationFailureMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "翻译失败：网络超时"
            case .networkConnectionLost, .notConnectedToInternet:
                return "翻译失败：网络中断"
            default:
                return "翻译失败：网络异常"
            }
        }
        if let translationError = error as? TranslationError {
            switch translationError {
            case .llmHTTPError(let statusCode, _) where statusCode >= 500:
                return "翻译失败：服务异常"
            case .llmHTTPError(let statusCode, _) where statusCode == 401 || statusCode == 403:
                return "翻译失败：API 鉴权"
            case .llmHTTPError(let statusCode, _) where statusCode == 429:
                return "翻译失败：请求过多"
            case .invalidLLMResponse, .llmResponseCountMismatch:
                return "翻译失败：返回无效"
            case .llmNotConfigured:
                return "翻译失败：API 未配置"
            case .invalidLLMEndpoint:
                return "翻译失败：地址无效"
            default:
                break
            }
        }
        return "翻译失败"
    }

    // MARK: - UI 桥接

    @MainActor
    private func showInteractiveOverlay(
        ocrCapture: CapturedScreenshot,
        displayImage: CGImage,
        selection: CGRect,
        displayScale: CGFloat,
        translationSettings: TranslationSettings
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let overlay = OverlayWindow()
            self.resultOverlay = overlay
            overlay.onDismiss = { [weak self] in
                self?.resultOverlay = nil
                continuation.resume()
            }
            overlay.onRetry = { [weak self, weak overlay] in
                guard let self else { return }
                ShotLensLogger.log("用户点击重试翻译")
                Task {
                    await self.translate(
                        captured: ocrCapture,
                        displayPixelSize: CGSize(width: displayImage.width, height: displayImage.height),
                        overlay: overlay,
                        settings: translationSettings
                    )
                }
            }
            overlay.onRetranslate = overlay.onRetry
            overlay.show(
                croppedScreenshot: displayImage,
                at: selection.origin,
                displayScale: displayScale
            )

            Task { [weak self, weak overlay] in
                guard let self else { return }
                await self.translate(
                    captured: ocrCapture,
                    displayPixelSize: CGSize(width: displayImage.width, height: displayImage.height),
                    overlay: overlay,
                    settings: translationSettings
                )
            }
        }
    }
}
