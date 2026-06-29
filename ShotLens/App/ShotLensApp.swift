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

        let capture = ScreenshotCapture()

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
            guard let snapshot = try await capture.captureFrozenDisplay() else {
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

        let captured: CapturedScreenshot?
        do {
            captured = try capture.crop(frozenSnapshot: frozenSnapshot, selection: selection)
        } catch {
            ShotLensLogger.log("冻结截图裁剪失败", error: error)
            return
        }

        guard let captured else {
            ShotLensLogger.log("冻结截图裁剪为空")
            return
        }

        let displayScale = max(
            CGFloat(captured.image.width) / max(selection.width, 1),
            CGFloat(captured.image.height) / max(selection.height, 1),
            1.0
        )

        await showInteractiveOverlay(
            captured: captured,
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
        displayScale: CGFloat,
        overlay: OverlayWindow?,
        settings: TranslationSettings
    ) async {
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

        guard !textBlocks.isEmpty else {
            ShotLensLogger.log("未识别到文字")
            overlay?.setMessage("未识别到文字")
            return
        }
        let layoutBlocks = TextLayoutOptimizer.merge(textBlocks)
        guard !layoutBlocks.isEmpty else {
            ShotLensLogger.log("OCR 文本块均被过滤，未形成可翻译布局块")
            overlay?.setMessage("未识别到文字")
            return
        }
        ShotLensLogger.log(String(format: "OCR 完成，原始 %d 个文本块，合并为 %d 个布局块，耗时 %.2fs", textBlocks.count, layoutBlocks.count, Date().timeIntervalSince(ocrStartedAt)))

        overlay?.setProcessing("正在翻译...")

        // 2. 确定源语言和目标语言
        let sourceLang = ShotLensLanguage.preferredSourceLanguage(for: layoutBlocks)
        let targetLang = Locale.preferredLanguages.first ?? "zh-Hans"

        let provider = TranslationProviderFactory.create(with: settings)
        let texts = layoutBlocks.map { $0.text }
        let translationStartedAt = Date()
        let translatedTexts: [String]
        do {
            translatedTexts = try await provider.translate(texts, from: sourceLang, to: targetLang)
        } catch {
            ShotLensLogger.log("翻译失败", error: error)
            overlay?.setMessage(userFacingTranslationFailureMessage(for: error))
            return
        }
        ShotLensLogger.log(String(format: "翻译完成，使用 %@，输出 %d 个文本块，耗时 %.2fs", provider.name, translatedTexts.count, Date().timeIntervalSince(translationStartedAt)))

        // 4. 组装 TranslatedBlock
        let translatedBlocks = zip(layoutBlocks, translatedTexts).map { (block, translation) in
            TranslatedBlock(original: block, translatedText: translation)
        }

        overlay?.setTranslatedBlocks(translatedBlocks)
    }

    private func userFacingTranslationFailureMessage(for error: Error) -> String {
        "翻译失败"
    }

    // MARK: - UI 桥接

    @MainActor
    private func showInteractiveOverlay(
        captured: CapturedScreenshot,
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
                        captured: captured,
                        displayScale: displayScale,
                        overlay: overlay,
                        settings: translationSettings
                    )
                }
            }
            overlay.show(
                croppedScreenshot: captured.image,
                at: selection.origin,
                displayScale: displayScale
            )

            Task { [weak self, weak overlay] in
                guard let self else { return }
                await self.translate(
                    captured: captured,
                    displayScale: displayScale,
                    overlay: overlay,
                    settings: translationSettings
                )
            }
        }
    }
}
