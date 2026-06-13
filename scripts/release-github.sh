#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${SHOTLENS_APP_VERSION:-$("$ROOT_DIR/scripts/next-release-version.sh")}"
DMG_PATH="$ROOT_DIR/build/release/ShotLens-$VERSION.dmg"

if [[ ! "$VERSION" =~ ^v[0-9]+(\.[0-9]+){1,2}$ ]]; then
  echo "Release version must look like v1.1 or v1.1.0, got: $VERSION" >&2
  exit 1
fi

if [[ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]]; then
  echo "Commit or stash local changes before creating a GitHub release." >&2
  exit 1
fi

if git -C "$ROOT_DIR" rev-parse "$VERSION" >/dev/null 2>&1; then
  echo "Tag already exists: $VERSION" >&2
  exit 1
fi

SHOTLENS_APP_VERSION="$VERSION" "$ROOT_DIR/scripts/package-dmg.sh" >/dev/null

git -C "$ROOT_DIR" tag "$VERSION"
git -C "$ROOT_DIR" push origin "$VERSION"

gh release create "$VERSION" "$DMG_PATH" \
  --repo qcsidios/ShotLens \
  --title "ShotLens $VERSION" \
  --notes "ShotLens $VERSION release build."

echo "$VERSION"
