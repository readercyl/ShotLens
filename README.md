# ShotLens

ShotLens 是一个轻量级 macOS 菜单栏截图翻译工具。

它会冻结当前屏幕，让你框选需要翻译的区域，在独立辅助进程中执行本地 OCR，再通过你配置的兼容 OpenAI 的 API 翻译识别到的文字，并把译文覆盖渲染回原截图。

## 功能

- 菜单栏常驻工具，支持全局快捷键触发
- 冻结屏幕后框选翻译区域
- 松开鼠标完成框选后，自动把原始选区截图写入系统剪贴板
- 基于 Apple Vision 的独立 OCR 辅助进程
- 把选区内识别到的非中文自然语言翻译为简体中文；中文、数字、代码和链接保持不变，并按完整语义块排版
- 翻译缩写与简写时会参考同一选区内的其他文字进行语境消歧
- 支持用户自定义的兼容 OpenAI API 翻译
- 支持填写 `/v1`、`/v1/chat/completions`、`/v1/models` 等常见 API 地址形式
- API 测试按钮会检查真实聊天补全端点，减少 `/models` 不可用和模型格式漂移造成的误报
- 模型字段可选：填写时显式传入，留空时由 API 服务商使用默认行为
- 译文按视觉语义块的像素坐标锚定；正常使用四周背景像素整体重建原文字区域，重建不可用时只在原始范围内使用采样背景兜底
- 可拖动的结果浮窗，支持重试、原文/译文切换、复制截图和纯文本译文
- 简洁控制台，用于查看权限、快捷键、开机启动和折叠式 API 设置
- 应用图标与 macOS 菜单栏模板图标
- 安装在“应用程序”目录时，启动后自动检查、下载并安装 GitHub Release 新版本；开发副本只提示、不自动替换

## 系统要求

- macOS 14.0 或更高版本
- Xcode 命令行工具
- 屏幕录制权限
- 自定义兼容 OpenAI 的聊天补全端点和 API 密钥；模型名称可选

## 使用说明

1. 启动 ShotLens 后，在菜单栏打开控制台。
2. 在 API 设置中填写自己的 API 地址、密钥和模型（模型可留空）。
3. 点击“测试”确认当前配置可用。
4. 授予屏幕录制权限。
5. 使用全局快捷键或菜单栏按钮开始截图翻译。
6. 框选区域后等待 OCR 和翻译完成，结果会显示在覆盖浮窗中。
7. 结果浮框右上角的透明 pin 图标会根据截图背景自动使用黑色或白色，并通过空心／实心表达钉住状态。钉住并翻译成功后，下侧控制区会自动隐藏。

## API 配置

ShotLens 使用你填写的兼容 OpenAI 聊天补全接口。地址和 Key 必填，模型可留空，由服务商使用默认模型；程序不会内置公共 Endpoint、Key 或模型。

API 地址可以填写为以下任意常见形式，程序会自动规范化为聊天补全请求地址：

```text
https://example.com/v1
https://example.com/v1/
https://example.com/v1/chat/completions
https://example.com/v1/models
```

连接测试会发送一个极小的聊天补全请求，用来验证地址、密钥和服务可用性。部分服务商不开放 `/models`，或模型偶尔没有按翻译格式返回，都不会再误判为 API 不可用。

API 面板里的“清空”会完全清除地址、Key 和模型。清空后需要重新配置自己的 API 才能开始截图翻译。

翻译输入使用最简单的稳定编号文本行，不再要求模型生成 JSON。一次请求会携带同一选区内的全部语义块作为上下文，每个语义块只对应一个坐标；返回优先按编号文本行解析，同时兼容编号对象、数组、代码块、常见箭头分隔、解释前缀、SSE 边缘残片、控制标记和不完整 JSON，并且不会追加网络修复请求。常规框选保持一次请求；超大选区按容量分批，但每批只请求一次。模型漏译或误答单个语义块时保留其他可靠译文，失败块继续显示原文。常见 UI 词会逐项在本地完成，只把未知文本发送给 API；同一 App 会话内完全相同的完整成功翻译最多缓存 128 批，退出后自动清空且不写入磁盘。产品名、型号和标识符允许合理保留英文。DeepSeek 官方接口会关闭思考模式并限制回复长度，避免翻译前生成无用推理。

浮框里的“重新翻译”会复用当前框选截图，但从 OCR 开始重新执行完整链路：重新识别、重新语义分组、重新调用翻译 API 和重新排版。整个过程不会再次截取屏幕，也不会要求用户重新框选。

ShotLens 默认继续使用 macOS Vision 在本机 OCR，并动态使用当前系统支持的识别语言；原图准确识别作为主结果，轻量灰度、对比度和锐化增强图只补回浅色漏字，截图像素仍不上传。框选较小时会自动增加 OCR 上下文，但最终只处理原始框选范围内的内容。每个包含非中文自然语言的完整语义块会发送给 API，模型翻译其中所有支持的外语并保留中文、数字、代码和链接后整体排版。

用户填写的 API 地址、Key 和模型会保存在 macOS 用户配置中。升级 App 不会清空这些配置；只有点击“清空”才会主动删除 API 设置。

## 更新

ShotLens 启动后会检查一次 GitHub Release。App 位于系统或用户“应用程序”目录时，发现新版会自动下载 `ShotLens-vX.Y.Z.dmg`，验证 bundle identifier、代码签名和与当前版本一致的指定签名要求，再暂存、备份、替换并重启；新版本无法启动时会恢复原 App。开发目录和临时目录中的副本只显示“升级”按钮，不会自动替换。运行期间仍每满 24 小时检查一次，但不会突然退出自动安装；控制台版本号旁保留手动检测和升级入口。

如果无法访问 GitHub，App 内更新检查会显示无法连接更新服务器，不影响截图翻译。无法使用 GitHub 的用户请使用你提供的飞书发布文档手动下载安装包。

## 构建

```bash
bash scripts/build-local.sh
```

脚本默认会使用固定的本地签名证书构建 `ShotLens.app` 到 `build/local`，保持屏幕录制权限连续。如需部署到其他目录，可设置 `SHOTLENS_DEPLOY_DIR`；只有明确需要 ad-hoc 签名时才传入 `SHOTLENS_CODESIGN_IDENTITY=-`。

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
bash scripts/check-translation-content.sh
bash scripts/check-ocr-selection-filter.sh
bash scripts/check-app-updater.sh
bash scripts/check-multi-display-capture.sh
bash scripts/check-clipboard-capture.sh
bash scripts/check-overlay-control-visibility.sh
bash scripts/check-overlay-geometry.sh
bash scripts/check-overlay-pin-appearance.sh
bash scripts/check-compact-ui.sh
bash scripts/check-project-integrity.sh
bash scripts/build-local.sh
bash scripts/check-no-private-config.sh
bash scripts/check-dmg-layout.sh
```

其中：

- `check-translation-endpoint.sh`：验证 API 地址规范化、翻译返回解析和连接测试链路。
- `check-translation-content.sh`：验证多语言完整上下文、跨行语义分组和多栏隔离。
- `check-ocr-selection-filter.sh`：验证原图与增强图双路识别、浅色文字、完整多语言行，以及边界残字和纯符号排除。
- `check-app-updater.sh`：验证 GitHub Release 新版本检测、版本比较和异常状态。
- `check-multi-display-capture.sh`：验证鼠标所在显示器的独立截图与 Retina/外接屏缩放尺寸。
- `check-clipboard-capture.sh`：验证框选完成后自动把原始选区截图写入剪贴板。
- `check-overlay-control-visibility.sh`：验证钉住、处理中、成功和失败状态下的下侧控制区显隐。
- `check-overlay-geometry.sh`：验证 OCR 像素坐标不漂移，并确保原文字形清除后仍保留背景纹理。
- `check-overlay-pin-appearance.sh`：验证钉住按钮在普通、悬停和已钉住状态下的外观。
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

`build/local`、测试目录、DMG 暂存目录和挂载残留可以在验证后清理；
`build/release` 中的正式安装包默认至少保留最新版。清理时不得删除整个
`build/`。只有已经核对 GitHub Release 存在同版本资产且明确决定不再保留
本地副本时，才可删除正式安装包。

## 隐私说明

ShotLens 会在本机完成截图、框选、OCR 和译文覆盖渲染。截图像素仅用于本地 OCR 和覆盖渲染；待翻译的非中文文字及同一语义块中用于保护的中文、数字、代码和链接会发送给你配置的 API 服务商。

请不要把个人 API 密钥写入源码、脚本或发行版说明。发布前建议运行 `scripts/check-no-private-config.sh` 检查源码和构建产物，确保没有任何 API Key 泄露。

## 仓库说明

构建产物、本地头脑风暴产物、内部计划文档和 Xcode 派生数据不纳入版本控制。

## 许可证

MIT
