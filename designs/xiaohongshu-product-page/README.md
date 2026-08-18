# ShotLens 小红书商品详情页

## 当前版本

- 当前正式版本由 `versions.json` 的 `currentVersion` 指定，目前为 `v4`。
- `versions/v4/index.html`：当前可编辑 HTML 母版。
- `versions/v4/mobile-preview.html`：手机宽度阅读预览。
- `versions/v4/shotlens-xhs-v4-complete.html`：可脱离项目目录单独发送和打开的完整 HTML。
- `versions/v4/exports/`：当前可上架 PNG。

## 版本与命名规则

- 每个版本独立保存在 `versions/vN/`，旧版本归档后不再覆盖。
- v4 不再保留独立 `00` 商品主图；`01-1x1.png` 是商品主图，`01-3x4.png` 是同视觉的轮播首图。
- `02.png`–`09.png` 是其余轮播，`10.png` 是长详情页；版本信息由所在目录承担。
- v1、v2 维持原有描述性文件名，避免无意义地改写历史版本。
- v1–v3 均作为历史版本保留，不因新规则改写旧产物。
- 新一轮修改先从当前版本复制为下一个版本，再修改和导出，禁止直接覆盖历史版本。
- `_d_meta.json` 保存设计工具记录，`versions.json` 是人工与脚本共同使用的版本真源。

## 预览与重新导出

在 ShotLens 仓库中启动静态服务器：

```bash
python3 -m http.server 4311 --directory designs
```

然后进入本目录并明确指定版本：

```bash
node export.mjs v4
```

不传版本时，脚本只导出 `versions.json` 中声明的当前版本；传入未登记版本会直接报错。

页面不包含价格、微信或站外联系方式。隐私边界、系统要求与翻译方向均使用有限定的准确表述。
