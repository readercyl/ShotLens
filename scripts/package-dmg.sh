#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ShotLens"
APP_VERSION="${SHOTLENS_APP_VERSION:-$("$ROOT_DIR/scripts/next-release-version.sh")}"
BUILD_DIR="$ROOT_DIR/build/release"
STAGING_DIR="$BUILD_DIR/dmg-staging"
DMG_PATH="$BUILD_DIR/ShotLens-$APP_VERSION.dmg"
CODESIGN_IDENTITY="${SHOTLENS_CODESIGN_IDENTITY:-}"

if [[ ! "$APP_VERSION" =~ ^v[0-9]+(\.[0-9]+){1,2}$ ]]; then
  echo "Release version must look like v1.1 or v1.1.0, got: $APP_VERSION" >&2
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$STAGING_DIR"

SHOTLENS_APP_VERSION="$APP_VERSION" SHOTLENS_DEPLOY_DIR="$STAGING_DIR" SHOTLENS_CODESIGN_IDENTITY="$CODESIGN_IDENTITY" "$ROOT_DIR/scripts/build-local.sh" >/dev/null
ln -s /Applications "$STAGING_DIR/Applications"

APP_PATH="$STAGING_DIR/$APP_NAME.app"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null
"$ROOT_DIR/scripts/check-dmg-layout.sh" "$STAGING_DIR"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "ShotLens $APP_VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null
hdiutil verify "$DMG_PATH" >/dev/null
xattr -cr "$DMG_PATH" 2>/dev/null || true
"$ROOT_DIR/scripts/check-no-private-config.sh" "$DMG_PATH" "$APP_PATH"

echo "$DMG_PATH"
