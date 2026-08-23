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
    private var activeFlowTask: Task<Void, Never>?
    private var activeTranslationTask: Task<Void, Never>?
    private var translationAttemptGate = PipelineAttemptGate()
    private var translationAttemptNumber = 0
    private var activeRun: ShotLensRunContext?
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
            ShotLensLogger.event(
                "hotkey_handler_install_failed",
                level: .error,
                stage: "hotkey",
                outcome: "failed",
                fields: ["error_number": String(status)]
            )
        }
    }

    private func registerGlobalHotKey() {
        guard hotKeyRef == nil else { return }
        guard hotKeyHandlerRef != nil else {
            ShotLensLogger.event(
                "hotkey_registration_blocked",
                level: .error,
                stage: "hotkey",
                outcome: "failed",
                fields: ["error_code": "hotkey.handler_missing"]
            )
            return
        }

        let hotKey = HotKey.loadSavedOrDefault()
        ShotLensLogger.event("hotkey_registration_started", stage: "hotkey")

        let status = RegisterEventHotKey(
            UInt32(hotKey.keyCode),
            UInt32(hotKey.modifiers),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            ShotLensLogger.event(
                "hotkey_registration_failed",
                level: .error,
                stage: "hotkey",
                outcome: "failed",
                fields: ["error_number": String(status)]
            )
            return
        }

        ShotLensLogger.event("hotkey_registration_completed", stage: "hotkey", outcome: "success")
    }

    private func unregisterGlobalHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
            ShotLensLogger.event("hotkey_unregistered", stage: "hotkey", outcome: "success")
        }
    }

    private func uninstallHotKeyHandler() {
        if let ref = hotKeyHandlerRef {
            RemoveEventHandler(ref)
            hotKeyHandlerRef = nil
        }
    }

    // MARK: - 主流程

    private func handleHotKey(trigger: String = "hotkey") {
        guard !isProcessing else {
            ShotLensLogger.event("capture_trigger_ignored", level: .warning, stage: "flow", outcome: "busy", fields: ["trigger": trigger])
            return
        }
        isProcessing = true
        translationAttemptNumber = 0
        let run = ShotLensLogger.startRun(trigger: trigger)
        activeRun = run

        // 确保最新设置已写入 UserDefaults，翻译链路才能读到
        mainWindowController.flushPendingSave()

        activeFlowTask = Task { [weak self] in
            guard let self else { return }
            let shouldReselect = await ShotLensLogger.withRun(run) {
                await self.executeTranslationFlow(run: run)
            }
            guard self.activeRun?.id == run.id else { return }
            self.activeFlowTask = nil
            self.activeRun = nil
            self.isProcessing = false
            ShotLensLogger.event(
                "run_finished",
                run: run,
                stage: "flow",
                outcome: shouldReselect ? "reselect" : "finished",
                fields: ["total_duration_ms": String(run.elapsedMilliseconds())]
            )
            if shouldReselect {
                self.handleHotKey(trigger: "reselect")
            }
        }
    }

    private func executeTranslationFlow(run: ShotLensRunContext) async -> Bool {
        // 从文本框直接抓设置，不依赖 UserDefaults 时序
        let translationSettings = mainWindowController.currentDraftSettings()

        guard translationSettings.isLLMConfigured else {
            let failure = PipelineFailurePresentation.make(kind: .apiNotConfigured)
            ShotLensLogger.event("configuration_missing", level: .warning, stage: "preflight", outcome: "failed", fields: ["recovery": "open_settings"])
            openMainWindow()
            mainWindowController.showPipelineFailure(failure)
            return false
        }

        let capture = ScreenshotCapture()
        let targetMouseLocation = NSEvent.mouseLocation

        guard capture.hasScreenCaptureAccess() else {
            ShotLensLogger.event("screen_permission_missing", level: .warning, stage: "preflight", outcome: "failed")
            openMainWindow()
            mainWindowController.showPipelineMessage("无法截取屏幕", detail: "请先开启屏幕录制权限。")
            return false
        }

        mainWindowController.hide()

        let frozenSnapshot: FrozenScreenshot
        let captureStartedAt = ProcessInfo.processInfo.systemUptime
        ShotLensLogger.event("capture_started", stage: "capture")
        do {
            guard let snapshot = try await capture.captureFrozenDisplay(containing: targetMouseLocation) else {
                presentPreOverlayFailure(.captureFailed, event: "capture_empty", error: nil)
                return false
            }
            frozenSnapshot = snapshot
        } catch {
            presentPreOverlayFailure(.captureFailed, event: "capture_failed", error: error)
            return false
        }
        ShotLensLogger.event(
            "capture_completed",
            stage: "capture",
            outcome: "success",
            fields: [
                "duration_ms": String(Int((ProcessInfo.processInfo.systemUptime - captureStartedAt) * 1_000)),
                "image_width": String(frozenSnapshot.image.width),
                "image_height": String(frozenSnapshot.image.height)
            ]
        )

        let selection: CGRect?
        let selectionStartedAt = ProcessInfo.processInfo.systemUptime
        ShotLensLogger.event("selection_started", stage: "selection")
        let selectionOverlay = InProcessSelectionOverlay()
        activeSelectionOverlay = selectionOverlay
        selection = await selectionOverlay.select(frozenScreenshot: frozenSnapshot)
        activeSelectionOverlay = nil

        guard let selection else {
            ShotLensLogger.event("selection_cancelled", stage: "selection", outcome: "cancelled")
            return false
        }
        ShotLensLogger.event(
            "selection_completed",
            stage: "selection",
            outcome: "success",
            fields: [
                "duration_ms": String(Int((ProcessInfo.processInfo.systemUptime - selectionStartedAt) * 1_000)),
                "selection_width": String(Int(selection.width.rounded())),
                "selection_height": String(Int(selection.height.rounded()))
            ]
        )

        let captureSelection = SelectionGeometry.expandedRect(
            for: selection,
            within: frozenSnapshot.screenRect
        )
        let ocrCapture: CapturedScreenshot?
        do {
            ocrCapture = try capture.crop(
                frozenSnapshot: frozenSnapshot,
                selection: captureSelection,
                userSelection: selection,
                writesPNG: false
            )
        } catch {
            presentPreOverlayFailure(.cropFailed, event: "ocr_crop_failed", error: error)
            return false
        }

        guard let ocrCapture else {
            presentPreOverlayFailure(.cropFailed, event: "ocr_crop_empty", error: nil)
            return false
        }

        let displayCapture: CapturedScreenshot?
        do {
            displayCapture = try capture.crop(
                frozenSnapshot: frozenSnapshot,
                selection: selection,
                writesPNG: false
            )
        } catch {
            displayCapture = nil
            ShotLensLogger.event("display_crop_failed", level: .error, stage: "crop", outcome: "failed", error: error)
        }
        guard let displayCapture else {
            presentPreOverlayFailure(.cropFailed, event: "display_crop_empty", error: nil)
            return false
        }
        ClipboardManager().copyImageToClipboard(image: displayCapture.image)
        ShotLensLogger.event("selection_copied", stage: "crop", outcome: "success")

        let displayScale = SelectionGeometry.displayScale(
            forPixelSize: CGSize(width: displayCapture.image.width, height: displayCapture.image.height),
            captureRect: selection
        )

        return await showInteractiveOverlay(
            ocrCapture: ocrCapture,
            displayImage: displayCapture.image,
            selection: selection,
            displayScale: displayScale,
            translationSettings: translationSettings,
            run: run
        )
    }

    private func presentPreOverlayFailure(
        _ kind: PipelineFailureKind,
        event: String,
        error: Error?
    ) {
        ShotLensLogger.event(event, level: .error, stage: "capture", outcome: "failed", error: error)
        let failure = PipelineFailurePresentation.make(kind: kind)
        openMainWindow()
        mainWindowController.showPipelineFailure(failure)
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
        settings: TranslationSettings,
        run: ShotLensRunContext,
        attemptID: UUID,
        onReselect: @escaping @MainActor () -> Void
    ) async {
        overlay?.setProcessing("正在识别文字...")

        let ocr = OCREngine()
        let ocrStartedAt = ProcessInfo.processInfo.systemUptime
        ShotLensLogger.event("ocr_started", stage: "ocr", fields: ["attempt": String(translationAttemptNumber)])
        let textBlocks: [TextBlock]
        do {
            textBlocks = try await ocr.recognize(image: captured.image)
            try Task.checkCancellation()
        } catch {
            finishTranslationAttempt(attemptID)
            if error is CancellationError { return }
            let kind = (error as? OCREngineError)?.failureKind ?? .ocrFailed
            ShotLensLogger.event("ocr_failed", level: .error, stage: "ocr", outcome: "failed", error: error)
            overlay?.setFailure(PipelineFailurePresentation.make(kind: kind))
            return
        }

        let selectedTextBlocks = textBlocks.filter {
            SelectionGeometry.shouldInclude($0.boundingBox, in: captured.userSelectionRectInImage)
        }
        guard !selectedTextBlocks.isEmpty else {
            finishTranslationAttempt(attemptID)
            ShotLensLogger.event("ocr_empty", level: .warning, stage: "ocr", outcome: "empty")
            overlay?.onRetry = onReselect
            overlay?.setFailure(PipelineFailurePresentation.make(kind: .noText))
            return
        }
        let displayTextBlocks = selectedTextBlocks.compactMap {
            SelectionGeometry.mapOCRBlockToDisplay(
                $0,
                userSelectionRectInOCR: captured.userSelectionRectInImage,
                displayPixelSize: displayPixelSize
            )
        }
        ShotLensLogger.event(
            "ocr_completed",
            stage: "ocr",
            outcome: "success",
            fields: [
                "duration_ms": String(Int((ProcessInfo.processInfo.systemUptime - ocrStartedAt) * 1_000)),
                "ocr_block_count": String(textBlocks.count),
                "selected_block_count": String(selectedTextBlocks.count),
                "display_block_count": String(displayTextBlocks.count)
            ]
        )
        let semanticBlocks = SemanticTextGrouper.merge(displayTextBlocks)
        let contentPlan = TranslationContentPlan.make(from: semanticBlocks)
        guard !contentPlan.sourceTexts.isEmpty else {
            finishTranslationAttempt(attemptID)
            ShotLensLogger.event("translation_content_empty", level: .warning, stage: "planning", outcome: "empty")
            overlay?.onRetry = onReselect
            overlay?.setFailure(PipelineFailurePresentation.make(kind: .noForeignText))
            return
        }
        let contextTexts: [String]
        if contentPlan.shouldUseNearbyContext {
            let contextCandidates = textBlocks.filter {
                !SelectionGeometry.shouldInclude($0.boundingBox, in: captured.userSelectionRectInImage)
            }
            contextTexts = TranslationContextBuilder.make(
                from: contextCandidates,
                excluding: contentPlan.sourceTexts
            )
        } else {
            contextTexts = []
        }
        let scenario = TranslationScenario.classify(sourceTexts: contentPlan.sourceTexts)
        ShotLensLogger.event(
            "translation_plan_completed",
            stage: "planning",
            outcome: "success",
            fields: [
                "scenario": scenario.rawValue,
                "semantic_block_count": String(semanticBlocks.count),
                "context_count": String(contextTexts.count),
                "total_count": String(contentPlan.sourceTexts.count),
                "character_count": String(contentPlan.sourceTexts.reduce(0) { $0 + $1.count })
            ]
        )

        configureTranslationRetry(
            contentPlan: contentPlan,
            contextTexts: contextTexts,
            overlay: overlay,
            settings: settings,
            run: run,
            existingTranslations: nil
        )
        await translateRecognized(
            contentPlan,
            contextTexts: contextTexts,
            overlay: overlay,
            settings: settings,
            run: run,
            attemptID: attemptID,
            existingTranslations: nil
        )
    }

    private func configureTranslationRetry(
        contentPlan: TranslationContentPlan,
        contextTexts: [String],
        overlay: OverlayWindow?,
        settings: TranslationSettings,
        run: ShotLensRunContext,
        existingTranslations: [String?]?
    ) {
        let retry = { [weak self, weak overlay] in
            guard let self else { return }
            self.startRecognizedTranslationAttempt(
                contentPlan: contentPlan,
                contextTexts: contextTexts,
                overlay: overlay,
                settings: settings,
                run: run,
                existingTranslations: existingTranslations
            )
        }
        overlay?.onRetry = retry
        overlay?.onRetranslate = retry
    }

    private func translateRecognized(
        _ contentPlan: TranslationContentPlan,
        contextTexts: [String],
        overlay: OverlayWindow?,
        settings: TranslationSettings,
        run: ShotLensRunContext,
        attemptID: UUID,
        existingTranslations: [String?]?
    ) async {
        overlay?.setProcessing("正在翻译...")

        // 2. 确定源语言和目标语言
        let sourceLang = "auto"
        let targetLang = "zh-Hans"

        let provider = TranslationProviderFactory.create(with: settings)
        let texts = contentPlan.sourceTexts
        var mergedTranslations = existingTranslations ?? [String?](repeating: nil, count: texts.count)
        if mergedTranslations.count != texts.count {
            mergedTranslations = [String?](repeating: nil, count: texts.count)
        }
        let pendingIndexes = texts.indices.filter { mergedTranslations[$0] == nil }
        let pendingTexts = pendingIndexes.map { texts[$0] }
        if pendingIndexes.isEmpty {
            finishTranslationAttempt(attemptID)
            if let translatedBlocks = contentPlan.applyingAvailable(mergedTranslations), !translatedBlocks.isEmpty {
                overlay?.setTranslatedBlocks(translatedBlocks, completedCount: texts.count, totalCount: texts.count)
            }
            return
        }
        if mergedTranslations.contains(where: { $0 != nil }),
           let existingBlocks = contentPlan.applyingAvailable(mergedTranslations),
           !existingBlocks.isEmpty {
            overlay?.setTranslationProgress(existingBlocks, completedCount: mergedTranslations.compactMap { $0 }.count, totalCount: texts.count)
        }
        let translationStartedAt = ProcessInfo.processInfo.systemUptime
        ShotLensLogger.event(
            "translation_started",
            stage: "translation",
            fields: [
                "attempt": String(translationAttemptNumber),
                "total_count": String(pendingTexts.count),
                "provider": provider.name
            ]
        )
        let translationResult: TranslationBatchResult
        do {
            translationResult = try await provider.translateAvailable(
                pendingTexts,
                context: contextTexts,
                from: sourceLang,
                to: targetLang,
                onProgress: { [weak overlay] partial in
                    var progressive = mergedTranslations
                    for (offset, index) in pendingIndexes.enumerated() where offset < partial.translations.count {
                        if let value = partial.translations[offset] { progressive[index] = value }
                    }
                    guard let partialBlocks = contentPlan.applyingAvailable(progressive),
                          !partialBlocks.isEmpty else { return }
                    overlay?.setTranslationProgress(
                        partialBlocks,
                        completedCount: progressive.compactMap { $0 }.count,
                        totalCount: texts.count
                    )
                }
            )
            try Task.checkCancellation()
        } catch {
            finishTranslationAttempt(attemptID)
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            let kind = translationFailureKind(for: error)
            let presentation = PipelineFailurePresentation.make(kind: kind)
            ShotLensLogger.event("translation_failed", level: .error, stage: "translation", outcome: "failed", error: error)
            if presentation.recovery == .openSettings {
                overlay?.onRetry = { [weak self, weak overlay] in
                    overlay?.requestDismiss()
                    self?.openMainWindow()
                    self?.mainWindowController.showPipelineFailure(presentation)
                }
            }
            overlay?.setFailure(presentation, keepsCurrentTranslation: mergedTranslations.contains { $0 != nil })
            return
        }
        for (offset, index) in pendingIndexes.enumerated() where offset < translationResult.translations.count {
            if let value = translationResult.translations[offset] { mergedTranslations[index] = value }
        }
        let completedCount = mergedTranslations.compactMap { $0 }.count
        guard let translatedBlocks = contentPlan.applyingAvailable(mergedTranslations),
              !translatedBlocks.isEmpty else {
            finishTranslationAttempt(attemptID)
            ShotLensLogger.event("translation_result_empty", level: .error, stage: "translation", outcome: "failed", fields: ["completed_count": String(completedCount), "total_count": String(texts.count)])
            overlay?.setFailure(PipelineFailurePresentation.make(kind: .invalidResponse))
            return
        }
        finishTranslationAttempt(attemptID)
        let isPartial = completedCount < texts.count
        configureTranslationRetry(
            contentPlan: contentPlan,
            contextTexts: contextTexts,
            overlay: overlay,
            settings: settings,
            run: run,
            existingTranslations: isPartial ? mergedTranslations : nil
        )
        let renderDuration = overlay?.setTranslatedBlocks(
            translatedBlocks,
            completedCount: completedCount,
            totalCount: texts.count
        ) ?? 0
        if isPartial {
            overlay?.setFailure(
                PipelineFailurePresentation.make(
                    kind: .partialTranslation,
                    completedCount: completedCount,
                    totalCount: texts.count
                ),
                keepsCurrentTranslation: true
            )
        }
        ShotLensLogger.event(
            "translation_completed",
            stage: "translation",
            outcome: isPartial ? "partial" : "success",
            fields: [
                "provider": provider.name,
                "completed_count": String(completedCount),
                "total_count": String(texts.count),
                "duration_ms": String(Int((ProcessInfo.processInfo.systemUptime - translationStartedAt) * 1_000)),
                "total_duration_ms": String(run.elapsedMilliseconds()),
                "render_mode": isPartial ? "partial" : "complete",
                "overflow_count": "0",
                "render_duration_ms": String(renderDuration)
            ]
        )
    }

    private func translationFailureKind(for error: Error) -> PipelineFailureKind {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .networkTimedOut
            case .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .dnsLookupFailed:
                return .networkDisconnected
            default:
                return .networkDisconnected
            }
        }
        if let translationError = error as? TranslationError {
            switch translationError {
            case .llmHTTPError(let statusCode) where statusCode >= 500:
                return .serviceUnavailable
            case .llmHTTPError(let statusCode) where statusCode == 401 || statusCode == 403:
                return .authenticationFailed
            case .llmHTTPError(let statusCode) where statusCode == 404:
                return .endpointOrModelNotFound
            case .llmHTTPError(let statusCode) where statusCode == 400 || statusCode == 422:
                return .requestRejected
            case .llmHTTPError(let statusCode) where statusCode == 408:
                return .networkTimedOut
            case .llmHTTPError(let statusCode) where statusCode == 429:
                return .rateLimited
            case .invalidLLMResponse, .llmResponseCountMismatch:
                return .invalidResponse
            case .llmNotConfigured:
                return .apiNotConfigured
            case .invalidLLMEndpoint:
                return .invalidEndpoint
            default:
                break
            }
        }
        return .unknownTranslation
    }

    private func startOCRTranslationAttempt(
        captured: CapturedScreenshot,
        displayPixelSize: CGSize,
        overlay: OverlayWindow?,
        settings: TranslationSettings,
        run: ShotLensRunContext,
        onReselect: @escaping @MainActor () -> Void
    ) {
        guard let attemptID = translationAttemptGate.begin() else {
            ShotLensLogger.event("translation_attempt_ignored", level: .warning, stage: "flow", outcome: "duplicate")
            return
        }
        translationAttemptNumber += 1
        activeTranslationTask = Task { [weak self, weak overlay] in
            guard let self else { return }
            await ShotLensLogger.withRun(run) {
                await self.translate(
                    captured: captured,
                    displayPixelSize: displayPixelSize,
                    overlay: overlay,
                    settings: settings,
                    run: run,
                    attemptID: attemptID,
                    onReselect: onReselect
                )
            }
            self.finishTranslationAttempt(attemptID)
        }
    }

    private func startRecognizedTranslationAttempt(
        contentPlan: TranslationContentPlan,
        contextTexts: [String],
        overlay: OverlayWindow?,
        settings: TranslationSettings,
        run: ShotLensRunContext,
        existingTranslations: [String?]?
    ) {
        guard let attemptID = translationAttemptGate.begin() else {
            ShotLensLogger.event("translation_attempt_ignored", level: .warning, stage: "translation", outcome: "duplicate")
            return
        }
        translationAttemptNumber += 1
        ShotLensLogger.event("translation_retry_started", stage: "translation", fields: ["attempt": String(translationAttemptNumber)])
        activeTranslationTask = Task { [weak self, weak overlay] in
            guard let self else { return }
            await ShotLensLogger.withRun(run) {
                await self.translateRecognized(
                    contentPlan,
                    contextTexts: contextTexts,
                    overlay: overlay,
                    settings: settings,
                    run: run,
                    attemptID: attemptID,
                    existingTranslations: existingTranslations
                )
            }
            self.finishTranslationAttempt(attemptID)
        }
    }

    private func finishTranslationAttempt(_ id: UUID) {
        translationAttemptGate.finish(id)
        if !translationAttemptGate.isRunning {
            activeTranslationTask = nil
        }
    }

    private func cancelActiveTranslation(run: ShotLensRunContext) {
        guard activeTranslationTask != nil || translationAttemptGate.isRunning else { return }
        activeTranslationTask?.cancel()
        activeTranslationTask = nil
        translationAttemptGate.cancel()
        ShotLensLogger.event("translation_cancelled", run: run, stage: "flow", outcome: "cancelled")
    }

    // MARK: - UI 桥接

    @MainActor
    private func showInteractiveOverlay(
        ocrCapture: CapturedScreenshot,
        displayImage: CGImage,
        selection: CGRect,
        displayScale: CGFloat,
        translationSettings: TranslationSettings,
        run: ShotLensRunContext
    ) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let overlay = OverlayWindow()
            var shouldReselect = false
            self.resultOverlay = overlay
            overlay.onDismiss = { [weak self] in
                self?.cancelActiveTranslation(run: run)
                self?.resultOverlay = nil
                continuation.resume(returning: shouldReselect)
            }
            let reselect: @MainActor () -> Void = { [weak overlay] in
                shouldReselect = true
                overlay?.requestDismiss()
            }
            let retryOCR: () -> Void = { [weak self, weak overlay] in
                guard let self else { return }
                self.startOCRTranslationAttempt(
                    captured: ocrCapture,
                    displayPixelSize: CGSize(width: displayImage.width, height: displayImage.height),
                    overlay: overlay,
                    settings: translationSettings,
                    run: run,
                    onReselect: reselect
                )
            }
            overlay.onRetry = retryOCR
            overlay.onRetranslate = retryOCR
            overlay.show(
                croppedScreenshot: displayImage,
                at: selection.origin,
                displayScale: displayScale
            )
            ShotLensLogger.event(
                "overlay_presented",
                run: run,
                stage: "overlay",
                outcome: "success",
                fields: ["duration_ms": String(run.elapsedMilliseconds())]
            )
            retryOCR()
        }
    }
}
