# 流动星夜壁纸

[English](README.md)

这是一个 macOS 26 的实验性动态壁纸扩展，带有 Metal 控制面板。它把你提供的图片和循环视频用于桌面与锁屏画面。

![流动星夜动画预览](docs/media/starry-night-preview.gif)

## 设置面板

在应用壁纸前，你可以在面板中调整流速和旋转幅度。

![可调整流速和幅度的流动星夜控制面板](docs/media/settings-panel.png)

## 下载

请到 [Starry Night v0.1.0](https://github.com/Rosemary1812/starry-night-wallpaper/releases/tag/v0.1.0) 下载，适用于搭载 Apple Silicon 的 macOS 26 Mac。Release 包含 ZIP 安装包和 SHA-256 校验文件。

这个版本使用 macOS 私有 API，未经过公证，也不适合 Mac App Store。macOS 可能要求你在 Finder 中按住 Control 点击应用，然后选择“打开”。后续 macOS 更新可能让扩展失效。

## 从源码构建

你需要一台运行 macOS 26 的 Apple Silicon Mac、Xcode Command Line Tools、一张可合法使用的图片和一个循环视频。

1. 创建 `assets/`。
2. 把图片放到 `assets/starrynight.jpg`。
3. 把视频放到 `assets/starry-night-flow.mp4`。
4. 运行 `zsh build.sh`。

构建会在仓库中生成 `Starry Night.app`，并使用 ad hoc 签名。脚本不会安装应用或修改当前壁纸。若要把素材放在其他位置，请在构建前把 `STARRY_ASSETS_DIR` 设为同时包含两个文件的目录。

仓库不包含构建所需的完整原始图片和视频。文档中的媒体只是缩小后的预览。请只使用你有权分发的素材。

## 使用

打开 `Starry Night.app`，然后在 **系统设置 > 壁纸** 中选择“Starry Night”。选中后由 macOS 管理扩展。要停用扩展，请选择另一张壁纸。

## 许可证和归属

仓库采用 MIT License。`WallpaperExtension/` 中的文件派生自 [Phosphene](https://github.com/kageroumado/phosphene) 的提交 `8b5bd57c1450eda74cf2ec6ceaae2e586cfdfcd6`，并保留其 MIT 许可证。请阅读 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) 了解本项目改动和限制。
