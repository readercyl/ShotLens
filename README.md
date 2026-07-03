# ShotLens

ShotLens 是一个轻量级 macOS 菜单栏截图翻译工具。

它会冻结当前屏幕，让你框选需要翻译的区域，在独立辅助进程中执行本地 OCR，再通过你配置的兼容 OpenAI 的 API 翻译识别到的文字，并把译文覆盖渲染回原截图。

## 功能

- 菜单栏常驻工具，支持全局快捷键触发
- 冻结屏幕后框选翻译区域
- 松开鼠标完成框选后，自动把原始选区截图写入系统剪贴板
- 基于 Apple Vision 的独立 OCR 辅助进程
- 固定识别英文并翻译为简体中文，支持单词、缩写、句子、段落和文章
- 翻译缩写与简写时会参考同一选区内的其他文字进行语境消歧
- 兼容 OpenAI 的 API 翻译，内置默认限免额度
- 支持填写 `/v1`、`/v1/chat/completions`、`/v1/models` 等常见 API 地址形式
- API 测试按钮会检查真实聊天补全端点，减少 `/models` 不可用和模型格式漂移造成的误报
- 模型字段可选：填写时显式传入，留空时由 API 服务商使用默认行为
- 针对 UI 文本、菜单、段落、文章和混合截图的布局感知渲染，译文严格在原 OCR 位置内呈现，避免跨区域重叠
- 可拖动的结果浮窗，支持重试、原文/译文切换、复制截图和纯文本译文
- 简洁控制台，用于查看权限、快捷键、开机启动和折叠式 API 设置
- 应用图标与 macOS 菜单栏模板图标
- 控制台内每天自动检查 GitHub Release 新版本，也可手动检查并升级

## 系统要求

- macOS 14.0 或更高版本
- Xcode 命令行工具
- 屏幕录制权限
- 可选：自定义兼容 OpenAI 的聊天补全端点、API 密钥和模型名称

## 使用说明

1. 启动 ShotLens 后，在菜单栏打开控制台。
2. 默认使用内置限免 API，地址、Key 和模型不会显示，也不能切换模型。
3. 如需使用自己的额度，可点击“自备 API”，在空白字段中填写 API 地址、密钥和模型。
4. 点击“测试”确认当前配置可用。
5. 授予屏幕录制权限。
6. 使用全局快捷键或菜单栏按钮开始截图翻译。
7. 框选区域后等待 OCR 和翻译完成，结果会显示在覆盖浮窗中。

## API 配置

ShotLens 使用兼容 OpenAI 的聊天补全接口。默认限免模式内置 SiliconFlow 地址、公共限免 Key 和 `tencent/Hunyuan-MT-7B` 模型，不在控制台显示这些信息，也不允许切换到其他模型；点击“自备 API”后，未配置过的地址、Key 和模型字段保持空白。

`tencent/Hunyuan-MT-7B` 当前为限免模型。若官方持续限免，默认限免功能会持续可用；若限免政策结束，该功能将停止。公共 Key 出现异常消耗时也可能随时停用，重度用户建议填写自己的 API Key。

API 地址可以填写为以下任意常见形式，程序会自动规范化为聊天补全请求地址：

```text
https://example.com/v1
https://example.com/v1/
https://example.com/v1/chat/completions
https://example.com/v1/models
```

连接测试会发送一个极小的聊天补全请求，用来验证地址、密钥和服务可用性。部分服务商不开放 `/models`，或模型偶尔没有按翻译格式返回，都不会再误判为 API 不可用。

自备 API 面板里的“清空”和“恢复默认”含义不同：“清空”会完全清除地址、Key 和模型，不再使用默认限免；“恢复默认”会重新启用内置限免配置并隐藏 API 详情。

翻译时会优先要求模型返回 JSON 数组；如果模型偶发返回编号列表、对象、代码块、解释前缀或数量不稳定，ShotLens 会自动修复格式并逐条兜底翻译，尽量避免整张截图失败。对于“被拒绝”“高风险”等明显像模型安全判定、而不是源文本翻译的输出，ShotLens 会拦截并重新修复，避免把误答覆盖到截图上。

用户自己填写的 API 地址、Key 和模型会保存在 macOS 用户配置中。升级 App 不会清空这些配置；只有点击“清空”或“恢复默认”才会主动改变 API 设置。

## 更新

ShotLens 启动后会自动检查一次 GitHub Release，此后每满 24 小时自动检查；控制台版本号旁也保留“检测新版本”按钮。自动检查只在发现新版时显示版本提示和“升级”按钮，点击后会下载 `ShotLens-vX.Y.Z.dmg` 并尝试自动替换当前 App。

如果无法访问 GitHub，App 内更新检查会显示无法连接更新服务器，不影响截图翻译。无法使用 GitHub 的用户请使用你提供的飞书发布文档手动下载安装包。

## 构建

```bash
bash scripts/build-local.sh
```

脚本默认会构建 `ShotLens.app` 到 `build/local`。如需部署到其他目录，可设置 `SHOTLENS_DEPLOY_DIR`。

打包 DMG：

```bash
SHOTLENS_APP_VERSION=v0.8.7 bash scripts/package-dmg.sh
```

发布前请先根据迭代内容选择版本号：破坏性或大版本能力使用 major，新增能力使用 minor，缺陷修复使用 patch。脚本要求显式设置 `SHOTLENS_APP_VERSION`，避免不经判断自动跳版本。DMG 顶层只包含 `ShotLens.app` 和应用程序文件夹快捷方式。

默认打包会跳过 Apple Developer ID 认证和公证，但不会使用 ad-hoc 临时签名。脚本会自动创建或复用本机 `ShotLens Local Signing` 自签名代码签名证书，让 macOS 能在后续升级中识别为同一个 App，减少屏幕录制权限反复丢失。

从旧 ad-hoc 版本第一次升级到本机稳定签名版本时，macOS 可能仍需要重新授权一次屏幕录制权限；完成这次授权后，只要后续版本继续使用同一个本机签名证书，权限不应每次升级都丢失。

如果后续要改用 Developer ID 证书，也可以显式指定签名身份：

```bash
SHOTLENS_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" bash scripts/package-dmg.sh
```

## 验证

```bash
bash scripts/check-translation-endpoint.sh
bash scripts/check-app-updater.sh
bash scripts/check-multi-display-capture.sh
bash scripts/check-clipboard-capture.sh
bash scripts/check-text-layout.sh
bash scripts/check-compact-ui.sh
bash scripts/check-project-integrity.sh
bash scripts/build-local.sh
bash scripts/check-no-private-config.sh
bash scripts/check-dmg-layout.sh
```

其中：

- `check-translation-endpoint.sh`：验证 API 地址规范化、翻译返回解析和连接测试链路。
- `check-app-updater.sh`：验证 GitHub Release 新版本检测、版本比较和异常状态。
- `check-multi-display-capture.sh`：验证鼠标所在显示器的独立截图与 Retina/外接屏缩放尺寸。
- `check-clipboard-capture.sh`：验证框选完成后自动把原始选区截图写入剪贴板。
- `check-text-layout.sh`：验证短词不会被误判为图标，并覆盖单词、句子、段落和文章布局。
- `check-compact-ui.sh`：验证 API 详情默认折叠、更新检测文字按钮和译文原位渲染约束。
- `check-project-integrity.sh`：检查关键项目文件、OCR 辅助进程、框选辅助进程和 Xcode 引用是否完整。
- `build-local.sh`：执行本地构建。
- `check-no-private-config.sh`：检查构建产物里没有泄露本机 API 配置。
- `check-release-signature.sh`：检查发布版不是 ad-hoc 签名，并带有稳定 bundle identifier 的签名要求。
- `check-dmg-layout.sh`：检查 DMG 目录布局。

## 创建发行版

命令行方式：

```bash
SHOTLENS_APP_VERSION=v0.8.7 bash scripts/release-github.sh
```

发布版本号必须使用三段式，例如 `v0.8.7`。发布前请先根据迭代内容决定版本号，并显式传入 `SHOTLENS_APP_VERSION`。

如果要为某个版本准备固定发布说明，可创建 `scripts/release-notes/vX.Y.Z.md`，发布脚本会自动使用它。

也可以手动创建 GitHub 发行版，但请使用已经按迭代内容确定的三段式 tag，并上传 `build/release/ShotLens-$VERSION.dmg`。

网页方式：打开 GitHub 仓库页面，进入发行版页面，新建发行版，创建或选择已经确定的 tag，填写标题和中文说明，上传 `build/release/ShotLens-$VERSION.dmg`，最后发布。

## 隐私说明

ShotLens 会在本机完成截图、框选、OCR 和译文覆盖渲染。截图像素仅用于本地 OCR 和覆盖渲染；OCR 识别出的文字会发送给默认或你配置的 API 服务商进行翻译。

请不要把个人 API 密钥写入源码、脚本或发行版说明。发布前建议运行 `scripts/check-no-private-config.sh` 检查构建产物；脚本只允许这枚明确声明的公共默认 Key。

## 仓库说明

构建产物、本地头脑风暴产物、内部计划文档和 Xcode 派生数据不纳入版本控制。

## 许可证

MIT
