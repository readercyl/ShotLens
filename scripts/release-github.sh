#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "${SHOTLENS_APP_VERSION:-}" ]]; then
  echo "SHOTLENS_APP_VERSION must be set after choosing the release version, for example v0.8.6." >&2
  exit 1
fi

VERSION="$SHOTLENS_APP_VERSION"
DMG_PATH="$ROOT_DIR/build/release/ShotLens-$VERSION.dmg"
RELEASE_NOTES_PATH="${SHOTLENS_RELEASE_NOTES_FILE:-$ROOT_DIR/scripts/release-notes/$VERSION.md}"

if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Release version must use three-part semver like v1.1.0, got: $VERSION" >&2
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

if [[ ! -f "$RELEASE_NOTES_PATH" ]]; then
  RELEASE_NOTES_PATH="$(mktemp)"
  trap 'rm -f "$RELEASE_NOTES_PATH"' EXIT
  cat > "$RELEASE_NOTES_PATH" <<EOF
## 更新内容

- ShotLens $VERSION 发布版本。

## 注意事项

- 默认福利 Key 可能限额、失效或被随时撤销，重度用户建议填写自己的 API Key。
- \`tencent/Hunyuan-MT-7B\` 当前限免，后续以 SiliconFlow/模型服务商政策为准。
EOF
fi

gh release create "$VERSION" "$DMG_PATH" \
  --repo readercyl/ShotLens \
  --title "ShotLens $VERSION" \
  --notes-file "$RELEASE_NOTES_PATH"

echo "$VERSION"
