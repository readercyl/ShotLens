#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MAIN_WINDOW="$ROOT_DIR/ShotLens/App/MainWindow.swift"
TRANSLATION_SETTINGS="$ROOT_DIR/ShotLens/Core/TranslationSettings.swift"
OVERLAY_WINDOW="$ROOT_DIR/ShotLens/Core/OverlayWindow.swift"
SELECTION_OVERLAY="$ROOT_DIR/ShotLens/Core/InProcessSelectionOverlay.swift"
SCREENSHOT_CAPTURE="$ROOT_DIR/ShotLens/Core/ScreenshotCapture.swift"
SHOTLENS_APP="$ROOT_DIR/ShotLens/App/ShotLensApp.swift"

rg -n 'apiDetailsExpandedKey' "$MAIN_WINDOW" >/dev/null
rg -n 'apiDetailsContainer' "$MAIN_WINDOW" >/dev/null
rg -n 'isApiDetailsExpanded = UserDefaults.standard.bool' "$MAIN_WINDOW" >/dev/null
rg -n 'toggleAPIExpandedClicked' "$MAIN_WINDOW" >/dev/null
rg -n 'updateWindowHeight' "$MAIN_WINDOW" >/dev/null
rg -n 'checkUpdateButton.title = "检测新版本"' "$MAIN_WINDOW" >/dev/null
rg -n 'checkUpdateButton.title = "检测中…"' "$MAIN_WINDOW" >/dev/null
rg -n 'flushPendingSave\(\)' "$MAIN_WINDOW" >/dev/null
rg -n 'syncAPIKeyDraftFromField' "$MAIN_WINDOW" >/dev/null
rg -n 'NSButton\(title: "清空"' "$MAIN_WINDOW" >/dev/null
rg -n 'NSButton\(title: "测试"' "$MAIN_WINDOW" >/dev/null
rg -n -F 'contentRect: NSRect(x: 0, y: 0, width: 430, height: 442)' "$MAIN_WINDOW" >/dev/null
rg -n -F 'row.widthAnchor.constraint(equalToConstant: 398)' "$MAIN_WINDOW" >/dev/null
rg -n -F 'card.widthAnchor.constraint(equalToConstant: 398)' "$MAIN_WINDOW" >/dev/null
rg -n -F 'icon.widthAnchor.constraint(equalToConstant: 58)' "$MAIN_WINDOW" >/dev/null
rg -n -F 'label("ShotLens", font: .systemFont(ofSize: 28, weight: .semibold))' "$MAIN_WINDOW" >/dev/null
rg -n -F 'recorder.widthAnchor.constraint(equalToConstant: 180)' "$MAIN_WINDOW" >/dev/null
rg -n -F 'let rightControl = makeRightControlContainer(width: 180)' "$MAIN_WINDOW" >/dev/null
if rg -n '用于冻结屏幕和框选翻译|按下后直接进入截图框选|登录 Mac 后自动启动 ShotLens' "$MAIN_WINDOW" >/dev/null; then
  echo "Primary settings cards should not keep secondary descriptions." >&2
  exit 1
fi
rg -n -F 'apiDetailsContainer?.isHidden = !isApiDetailsExpanded' "$MAIN_WINDOW" >/dev/null
rg -n -F 'toggleAPIButton.title = isApiDetailsExpanded ? "收起" : "展开"' "$MAIN_WINDOW" >/dev/null
rg -n 'scheduleAutomaticUpdateChecks' "$MAIN_WINDOW" >/dev/null
rg -n 'performAutomaticUpdateCheckIfNeeded' "$MAIN_WINDOW" >/dev/null
rg -n 'automaticallyInstalls: true' "$MAIN_WINDOW" >/dev/null
rg -n 'canAutomaticallyInstall' "$MAIN_WINDOW" >/dev/null

if rg -n 'showReleaseNotesIfNeeded|lastShownReleaseNotesVersionKey|更新完成' "$SHOTLENS_APP" >/dev/null; then
  echo "App launch must not show automatic release/update reminder popups." >&2
  exit 1
fi
if rg -n '截图翻译控制台' "$MAIN_WINDOW" >/dev/null; then
  echo "Main window should not repeat 截图翻译控制台 in the header." >&2
  exit 1
fi
if rg -n 'checkUpdateIconView|arrow.clockwise|CABasicAnimation|shotlens.update.spin' "$MAIN_WINDOW" >/dev/null; then
  echo "Update check should use a text button, not a spinning icon." >&2
  exit 1
fi
rg -n 'OverlayPinButton' "$OVERLAY_WINDOW" >/dev/null
rg -n 'let statusWindow = OverlayStatusWindow' "$OVERLAY_WINDOW" >/dev/null
rg -n 'let pinWindow = OverlayPinWindow' "$OVERLAY_WINDOW" >/dev/null
rg -n 'showSaveWindow' "$OVERLAY_WINDOW" >/dev/null
rg -n 'window\.addChildWindow\(statusWindow, ordered: \.above\)' "$OVERLAY_WINDOW" >/dev/null
rg -n 'window\.addChildWindow\(pinWindow, ordered: \.above\)' "$OVERLAY_WINDOW" >/dev/null
if rg -n 'statusWindow\?\.updateAnchorRect|saveWindow\?\.updateStatusFrame' "$OVERLAY_WINDOW" >/dev/null; then
  echo "Result controls must follow as child windows, not through manual move callbacks." >&2
  exit 1
fi
if rg -n 'NSColor\.system(?:Blue|Green|Orange).*setFill' "$OVERLAY_WINDOW" >/dev/null; then
  echo "Overlay action buttons must use one neutral color." >&2
  exit 1
fi
rg -n 'pinButton\.toolTip = "钉住浮框"' "$OVERLAY_WINDOW" >/dev/null
rg -n 'toolTip = isPinned \? "解除钉住" : "钉住浮框"' "$OVERLAY_WINDOW" >/dev/null
rg -n 'copyTextButton\.toolTip = "复制译文"' "$OVERLAY_WINDOW" >/dev/null
rg -n 'retranslateButton\.toolTip = "重新翻译"' "$OVERLAY_WINDOW" >/dev/null
rg -n 'saveButton\.toolTip = "复制截图"' "$OVERLAY_WINDOW" >/dev/null
rg -n 'applyControlVisibility' "$OVERLAY_WINDOW" >/dev/null
rg -n 'dismissFromOutsideClick' "$OVERLAY_WINDOW" >/dev/null
rg -n 'onRetranslate' "$OVERLAY_WINDOW" "$SHOTLENS_APP" >/dev/null
rg -n 'overlay\.onRetranslate = overlay\.onRetry' "$SHOTLENS_APP" >/dev/null
RETRY_BLOCK="$(sed -n '/overlay\.onRetry =/,/overlay\.onRetranslate =/p' "$SHOTLENS_APP")"
grep -F 'await self.translate(' <<<"$RETRY_BLOCK" >/dev/null
grep -F 'captured: ocrCapture' <<<"$RETRY_BLOCK" >/dev/null
if grep -E 'captureFrozenDisplay|executeTranslationFlow|startCapture' <<<"$RETRY_BLOCK" >/dev/null; then
  echo "Retranslate must re-run OCR from the existing captured image without taking a new screenshot." >&2
  exit 1
fi
rg -n 'translateRecognized' "$SHOTLENS_APP" >/dev/null
if rg -n 'NSApp\.activate\(ignoringOtherApps: true\)' "$OVERLAY_WINDOW" >/dev/null; then
  echo "Result overlay must not activate the main app because activation can switch away from fullscreen Spaces." >&2
  exit 1
fi
rg -n 'NSPanel' "$OVERLAY_WINDOW" "$SELECTION_OVERLAY" >/dev/null
rg -n 'nonactivatingPanel' "$OVERLAY_WINDOW" "$SELECTION_OVERLAY" >/dev/null
rg -n 'screenSaver' "$OVERLAY_WINDOW" "$SELECTION_OVERLAY" >/dev/null
rg -n '\.stationary' "$OVERLAY_WINDOW" "$SELECTION_OVERLAY" >/dev/null
rg -n 'override func acceptsFirstMouse' "$SELECTION_OVERLAY" >/dev/null
if rg -n 'for screen in screens' "$SELECTION_OVERLAY" >/dev/null; then
  echo "Selection overlay must only cover the screen under the mouse." >&2
  exit 1
fi
rg -n 'import ScreenCaptureKit' "$SCREENSHOT_CAPTURE" >/dev/null
rg -n 'SCScreenshotManager' "$SCREENSHOT_CAPTURE" >/dev/null
if rg -n '/usr/sbin/screencapture|CGWindowListCreateImage|CGDisplayCreateImage|process\.executableURL|process\.run\(\)' "$SCREENSHOT_CAPTURE" >/dev/null; then
  echo "Primary screenshot capture must stay in-process; external screencapture causes visible Space/window refresh." >&2
  exit 1
fi
if rg -n 'SelectionClient\(\)\.select|ShotLensSelect' "$SHOTLENS_APP" "$ROOT_DIR/ShotLens/Core" "$ROOT_DIR/scripts/build-local.sh" >/dev/null; then
  echo "Primary selection flow must stay in-process; cold-launching ShotLensSelect can cause a visible flash." >&2
  exit 1
fi
rg -n 'InProcessSelectionOverlay' "$SHOTLENS_APP" "$SELECTION_OVERLAY" >/dev/null
rg -n 'OverlayGeometry\.displayRect' "$OVERLAY_WINDOW" >/dev/null
rg -n 'OverlayTextBackgroundRestorer\.restoredPatch' "$OVERLAY_WINDOW" >/dev/null
rg -n 'drawFallbackBackground' "$OVERLAY_WINDOW" >/dev/null
rg -n -U '} else \{\n\s+drawFallbackBackground' "$OVERLAY_WINDOW" >/dev/null
rg -n 'sampledBackgroundColor' "$OVERLAY_WINDOW" >/dev/null
rg -n 'resolvedTextColor' "$OVERLAY_WINDOW" >/dev/null
rg -n 'var best = minimumSize' "$OVERLAY_WINDOW" >/dev/null
if rg -n 'backgroundColor\.setFill|NSBezierPath\(rect: layout\.' "$OVERLAY_WINDOW" >/dev/null; then
  echo "Translated text must not render on a solid background block." >&2
  exit 1
fi

echo "Compact UI check passed."
