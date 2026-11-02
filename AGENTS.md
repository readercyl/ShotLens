# ShotLens · 代码仓库规则

- 本地构建一律用 `bash scripts/build-local.sh`（默认 development 身份，产物 `build/local/ShotLens 开发版.app`）。
- `SHOTLENS_BUILD_KIND=release` 只用于打包和发布准备，产物留在 `build/local/ShotLens.app`。**不要把任何本地构建复制进 `/Applications` 或 `~/Applications`**；正式安装只由发布流程完成。脚本会在未显式设置 `SHOTLENS_ALLOW_SYSTEM_INSTALL=1` 时拒绝安装到应用目录。
- 开发期验证权限、屏幕录制、钥匙串和自动更新，一律使用开发版身份；不要用 release 身份覆盖用户正在使用的正式版。
- 翻译 API Key 存在钥匙串，条目 ACL 对任意应用开放（`SecAccessCreate` + 首次读取后就地放开）。改存储逻辑时保持这一性质，不要再引入“每次重新构建都要授权”的条目。
- 签名统一使用 `scripts/ensure-local-signing-cert.sh` 提供的本机证书；不要新增 ad-hoc 签名路径，也不要重新生成证书（换证书会让屏幕录制等系统授权失效一次）。
