#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ShotLens"
BUILD_DIR="$ROOT_DIR/build/release"
CODESIGN_IDENTITY="${SHOTLENS_CODESIGN_IDENTITY:-}"

if [[ -z "${SHOTLENS_APP_VERSION:-}" ]]; then
  echo "SHOTLENS_APP_VERSION must be set after choosing the release version, for example v0.8.6." >&2
  exit 1
fi

APP_VERSION="$SHOTLENS_APP_VERSION"
STAGING_DIR="$BUILD_DIR/dmg-staging-$APP_VERSION"
DMG_PATH="$BUILD_DIR/ShotLens-$APP_VERSION.dmg"
RAW_DMG_PATH="$BUILD_DIR/ShotLens-$APP_VERSION.raw.dmg"

if [[ ! "$APP_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Release version must use three-part semver like v1.1.0, got: $APP_VERSION" >&2
  exit 1
fi

rm -rf "$STAGING_DIR"
rm -f "$DMG_PATH" "$RAW_DMG_PATH"
mkdir -p "$STAGING_DIR"

if [[ -z "$CODESIGN_IDENTITY" ]]; then
  CODESIGN_IDENTITY="$("$ROOT_DIR/scripts/ensure-local-signing-cert.sh")"
  echo "Using local release signing identity: $CODESIGN_IDENTITY" >&2
fi

SHOTLENS_APP_VERSION="$APP_VERSION" SHOTLENS_DEPLOY_DIR="$STAGING_DIR" SHOTLENS_CODESIGN_IDENTITY="$CODESIGN_IDENTITY" "$ROOT_DIR/scripts/build-local.sh" >/dev/null
ln -s /Applications "$STAGING_DIR/Applications"

APP_PATH="$STAGING_DIR/$APP_NAME.app"
"$ROOT_DIR/scripts/check-release-signature.sh" "$APP_PATH"
"$ROOT_DIR/scripts/check-dmg-layout.sh" "$STAGING_DIR"

rm -f "$DMG_PATH"
hdiutil makehybrid \
  -hfs \
  -hfs-volume-name "ShotLens $APP_VERSION" \
  -o "$RAW_DMG_PATH" \
  "$STAGING_DIR" >/dev/null
hdiutil convert "$RAW_DMG_PATH" -format UDZO -o "$DMG_PATH" >/dev/null
rm -f "$RAW_DMG_PATH"
hdiutil verify "$DMG_PATH" >/dev/null
xattr -cr "$DMG_PATH" 2>/dev/null || true
"$ROOT_DIR/scripts/check-no-private-config.sh" "$DMG_PATH" "$APP_PATH"

echo "$DMG_PATH"
