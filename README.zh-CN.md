# 流动星夜壁纸

[English](README.md)

这是一个 macOS 26 的实验性动态壁纸扩展，带有 Metal 控制面板。选择画作、调整动效后，应用会生成用于桌面与锁屏的循环视频。

![流动星夜动画预览](docs/media/starry-night-preview.gif)

## 画作集

除梵高《星空》外，还包含以下四幅。动效保持轻微，使用遮罩保护画面主体。

### 莫奈 · 睡莲（1906）

水面与倒影轻轻荡漾，主要睡莲花簇保持静止。

![睡莲动态预览](docs/media/water-lilies.gif)

### 莫奈 · 麦草堆：日落与雪景（1890–91）

天空与夕照轻微变化，草堆和雪地保持静止。

![麦草堆动态预览](docs/media/wheat-stacks.gif)

### 梵高 · 罗讷河上的星夜（1888）

河面与灯光倒影轻轻摇曳，岸线、船桅和前景人物保持静止。

![罗讷河上的星夜动态预览](docs/media/rhone.gif)

### 梵高 · 有柏树的麦田（1889）

云层与麦浪缓缓流动，主要柏树和中间山丘保持静止。

![有柏树的麦田动态预览](docs/media/cypresses.gif)

## 设置面板

在应用壁纸前，你可以选择画作、调整流速和动效幅度。宽屏会裁切画作以铺满屏幕，预览同样采用铺满显示。

![可调整流速和幅度的流动星夜控制面板](docs/media/settings-panel.png)

## 下载

请到 [GitHub Releases](https://github.com/Rosemary1812/starry-night-wallpaper/releases) 下载，适用于搭载 Apple Silicon 的 macOS 26 Mac。Release 包含 ZIP 安装包和 SHA-256 校验文件。原有 v0.1.0 仅包含《星空》。

这个版本使用 macOS 私有 API，未经过公证，也不适合 Mac App Store。macOS 可能要求你在 Finder 中按住 Control 点击应用，然后选择“打开”。后续 macOS 更新可能让扩展失效。

## 从源码构建

你需要一台运行 macOS 26 的 Apple Silicon Mac、Xcode Command Line Tools、一张可合法使用的图片和一个循环视频。

1. 创建 `assets/`。
2. 把图片放到 `assets/starrynight.jpg`。
3. 把视频放到 `assets/starry-night-flow.mp4`。
4. 运行 `zsh scripts/fetch-artworks.sh` 下载新增的四幅公版画作素材。
5. 运行 `zsh build.sh`。

构建会在仓库中生成 `Starry Night.app`，并使用 ad hoc 签名。脚本不会安装应用或修改当前壁纸。若要把素材放在其他位置，请在下载和构建前把 `STARRY_ASSETS_DIR` 设为包含全部图片与视频素材的目录。

仓库不包含构建所需的完整原始图片和视频。文档中的媒体只是缩小后的预览。请只使用你有权分发的素材。

## 使用

打开 `Starry Night.app`，选择画作并点击“应用到桌面与锁屏”。在 **系统设置 > 壁纸** 中选择“流动星夜”，并将屏幕保护程序设为与壁纸相同，以启用锁屏效果。切换画作或调整滑块只更新预览，再次应用后才更新系统壁纸。控制面板目前为中文。

也可以只导出 MP4，不修改系统壁纸。运行 `zsh scripts/verify-artworks.sh` 可检查五幅画的循环首尾、保护区域和运动，截图保存在 `dist/evidence/`。这些渲染检查不覆盖 macOS 锁屏播放。

## 许可证和归属

仓库采用 MIT License。`WallpaperExtension/` 中的文件派生自 [Phosphene](https://github.com/kageroumado/phosphene) 的提交 `8b5bd57c1450eda74cf2ec6ceaae2e586cfdfcd6`，并保留其 MIT 许可证。请阅读 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) 了解本项目改动和限制。
