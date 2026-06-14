# ShotLens

ShotLens 是一个轻量级 macOS 菜单栏截图翻译工具。

它会冻结当前屏幕，让你框选需要翻译的区域，在独立辅助进程中执行本地 OCR，再通过你配置的兼容 OpenAI 的 API 翻译识别到的文字，并把译文覆盖渲染回原截图。

## 功能

- 菜单栏常驻工具，支持全局快捷键触发
- 冻结屏幕后框选翻译区域
- 基于 Apple Vision 的独立 OCR 辅助进程
- 兼容 OpenAI 的 API 翻译，内置默认福利额度
- 支持填写 `/v1`、`/v1/chat/completions`、`/v1/models` 等常见 API 地址形式
- API 测试按钮会检查真实聊天补全端点，减少 `/models` 不可用造成的误报
- 模型字段可选：填写时显式传入，留空时由 API 服务商使用默认行为
- 针对 UI 文本、菜单、段落、文章和混合截图的布局感知渲染
- 可拖动的结果浮窗，支持重试、原文/译文切换、复制截图和纯文本译文
- 简洁控制台，用于查看权限、快捷键、开机启动和 API 设置
- 应用图标与 macOS 菜单栏模板图标
- 控制台内手动检查 GitHub Release 新版本并升级

## 系统要求

- macOS 14.0 或更高版本
- Xcode 命令行工具
- 屏幕录制权限
- 可选：自定义兼容 OpenAI 的聊天补全端点、API 密钥和模型名称

## 使用说明

1. 启动 ShotLens 后，在菜单栏打开控制台。
2. 默认 API 地址和模型已预置，Key 留空时使用默认福利额度。
3. 如需使用自己的额度，可在“API 信息”里填写 API 密钥，也可以改 API 地址和模型。
4. 点击“测试”确认当前配置可用。
5. 授予屏幕录制权限。
6. 使用全局快捷键或菜单栏按钮开始截图翻译。
7. 框选区域后等待 OCR 和翻译完成，结果会显示在覆盖浮窗中。

## API 配置

ShotLens 使用兼容 OpenAI 的聊天补全接口。默认使用 SiliconFlow 地址 `https://api.siliconflow.cn/v1` 和模型 `tencent/Hunyuan-MT-7B`。Key 输入框留空时，应用会使用内置公共福利 Key；这个 Key 可能限额、失效或被随时撤销，重度用户建议填写自己的 API Key。

`tencent/Hunyuan-MT-7B` 当前为限免模型，后续可用性和计费以 SiliconFlow/模型服务商政策为准。

API 地址可以填写为以下任意常见形式，程序会自动规范化为聊天补全请求地址：

```text
https://example.com/v1
https://example.com/v1/
https://example.com/v1/chat/completions
https://example.com/v1/models
```

连接测试会发送一个极小的聊天补全请求，用来验证地址、密钥和服务可用性。部分服务商不开放 `/models`，这不会再影响测试结果。

## 更新

控制台版本号旁的圆形箭头用于手动检查 GitHub Release 新版本。发现新版后会显示“升级”按钮，点击后下载 `ShotLens-vX.Y.Z.dmg` 并尝试自动替换当前 App。

如果无法访问 GitHub，App 内更新检查会显示无法连接更新服务器，不影响截图翻译。无法使用 GitHub 的用户请使用你提供的飞书发布文档手动下载安装包。

## 构建

```bash
bash scripts/build-local.sh
```

脚本默认会构建 `ShotLens.app` 到 `build/local`。如需部署到其他目录，可设置 `SHOTLENS_DEPLOY_DIR`。

打包 DMG：

```bash
bash scripts/package-dmg.sh
```

脚本会基于已有 `v*` tag 自动计算下一个版本。例如当前最新 tag 为 `v1.1` 时，会输出 `build/release/ShotLens-v1.2.dmg`。如果要指定版本，可设置 `SHOTLENS_APP_VERSION=v1.2`。DMG 顶层只包含 `ShotLens.app` 和应用程序文件夹快捷方式。

## 验证

```bash
bash scripts/check-translation-endpoint.sh
bash scripts/check-app-updater.sh
bash scripts/check-project-integrity.sh
bash scripts/build-local.sh
bash scripts/check-no-private-config.sh
bash scripts/check-dmg-layout.sh
```

其中：

- `check-translation-endpoint.sh`：验证 API 地址规范化、翻译返回解析和连接测试链路。
- `check-app-updater.sh`：验证 GitHub Release 新版本检测、版本比较和异常状态。
- `check-project-integrity.sh`：检查关键项目文件、OCR 辅助进程、框选辅助进程和 Xcode 引用是否完整。
- `build-local.sh`：执行本地构建。
- `check-no-private-config.sh`：检查构建产物里没有泄露本机 API 配置。
- `check-dmg-layout.sh`：检查 DMG 目录布局。

## 创建发行版

命令行方式：

```bash
VERSION="$(bash scripts/next-release-version.sh)"
SHOTLENS_APP_VERSION="$VERSION" bash scripts/package-dmg.sh
git tag "$VERSION"
git push origin "$VERSION"
gh release create "$VERSION" "build/release/ShotLens-$VERSION.dmg" \
  --title "ShotLens $VERSION" \
  --notes "ShotLens $VERSION 发布版本。"
```

也可以在已提交、干净的工作区里一键创建 GitHub 发行版：

```bash
bash scripts/release-github.sh
```

网页方式：打开 GitHub 仓库页面，进入发行版页面，新建发行版，创建或选择 `scripts/next-release-version.sh` 输出的 tag，填写标题和中文说明，上传 `build/release/ShotLens-$VERSION.dmg`，最后发布。

## 隐私说明

ShotLens 会在本机完成截图、框选、OCR 和译文覆盖渲染。截图像素仅用于本地 OCR 和覆盖渲染；OCR 识别出的文字会发送给默认或你配置的 API 服务商进行翻译。

请不要把个人 API 密钥写入源码、脚本或发行版说明。发布前建议运行 `scripts/check-no-private-config.sh` 检查构建产物；脚本只允许这枚明确声明的公共默认 Key。

## 仓库说明

构建产物、本地头脑风暴产物、内部计划文档和 Xcode 派生数据不纳入版本控制。

## 许可证

MIT
