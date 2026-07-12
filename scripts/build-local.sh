#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ShotLens"
APP_VERSION="${SHOTLENS_APP_VERSION:-v1.1.1}"
BUNDLE_SHORT_VERSION="${APP_VERSION#v}"
APP_BUILD="${SHOTLENS_APP_BUILD:-1}"
MIN_MACOS_VERSION="14.0"
SWIFT_TARGET="arm64-apple-macosx$MIN_MACOS_VERSION"
BUILD_DIR="$ROOT_DIR/build/local"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE="$MACOS_DIR/$APP_NAME"
OCR_EXECUTABLE="$MACOS_DIR/ShotLensOCR"
DEPLOY_DIR="${SHOTLENS_DEPLOY_DIR:-$BUILD_DIR}"
DEPLOY_APP_DIR="$DEPLOY_DIR/$APP_NAME.app"
CODESIGN_IDENTITY="${SHOTLENS_CODESIGN_IDENTITY:-}"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

APP_SWIFT_SOURCES=()
while IFS= read -r source_file; do
  APP_SWIFT_SOURCES+=("$source_file")
done < <(find "$ROOT_DIR/ShotLens" -name '*.swift' ! -path "$ROOT_DIR/ShotLens/Tools/*" | sort)

swiftc \
  -O \
  -target "$SWIFT_TARGET" \
  "${APP_SWIFT_SOURCES[@]}" \
  -o "$EXECUTABLE"

swiftc \
  -O \
  -target "$SWIFT_TARGET" \
  -parse-as-library \
  "$ROOT_DIR/ShotLens/Tools/ShotLensOCR.swift" \
  -o "$OCR_EXECUTABLE"

cp "$ROOT_DIR/ShotLens/Resources/ShotLens.icns" "$RESOURCES_DIR/ShotLens.icns"
cp "$ROOT_DIR/ShotLens/Resources/ShotLensMenuBarTemplate.png" "$RESOURCES_DIR/ShotLensMenuBarTemplate.png"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh-Hans</string>
    <key>CFBundleDisplayName</key>
    <string>ShotLens</string>
    <key>CFBundleExecutable</key>
    <string>ShotLens</string>
    <key>CFBundleIconFile</key>
    <string>ShotLens.icns</string>
    <key>CFBundleIdentifier</key>
    <string>com.qingcheng.shotlens.mac</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>ShotLens</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$BUNDLE_SHORT_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS_VERSION</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>瞬译需要截取屏幕内容以进行文字识别和翻译。截图用于本机 OCR，识别后的文本会发送到你配置的 API 进行翻译。</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

chmod +x "$EXECUTABLE" "$OCR_EXECUTABLE"
if [[ -n "$CODESIGN_IDENTITY" ]]; then
  codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_DIR" >/dev/null
else
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

mkdir -p "$DEPLOY_DIR"
if [[ "$DEPLOY_APP_DIR" != "$APP_DIR" ]]; then
  rm -rf "$DEPLOY_APP_DIR"
  ditto "$APP_DIR" "$DEPLOY_APP_DIR"
  xattr -dr com.apple.quarantine "$DEPLOY_APP_DIR" 2>/dev/null || true
  if [[ -n "$CODESIGN_IDENTITY" ]]; then
    codesign --force --deep --sign "$CODESIGN_IDENTITY" "$DEPLOY_APP_DIR" >/dev/null
  else
    codesign --force --deep --sign - "$DEPLOY_APP_DIR" >/dev/null
  fi
fi

echo "$DEPLOY_APP_DIR"
