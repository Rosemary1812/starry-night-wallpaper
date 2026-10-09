![StarryNight，画作在流动](docs/media/readme-header.png)

# StarryNight

[English](README.md) · [下载应用](https://github.com/Rosemary1812/starry-night-wallpaper/releases) · [画作来源](THIRD-PARTY-NOTICES.md)

让画作成为 Mac 上的动态壁纸。StarryNight 用原生画廊展示作品，再通过 Metal 渲染动效：云层沿着笔触流动，水面与倒影起伏，前景主体保持静止。

当前源码包含 **12 幅画作**、无限循环滚动的画廊、每幅画的实时动态预览，以及取自《星空》的黑白应用图标。界面支持简体中文、繁體中文和 English。

![当前 Metal 渲染器中的《星空》动态壁纸](docs/media/starry-night-preview.gif)

## 浏览画作

向任意方向滚动或拖动，都可以继续浏览，不会停在第一幅或最后一幅。点击缩略图、左右箭头，或按键盘方向键切换画作。选定画作后，实时动态预览开始播放；旁边的画作保持静态。

![十二幅画作的当前动态壁纸循环](docs/media/painting-collection.gif)

上面的 GIF 使用默认速度与强度，展示完整的 24 秒循环。帧画面直接来自当前应用的 Metal 渲染器，README 预览降采样为 4 fps，实际壁纸视频为 30 fps。这些是渲染器画面，不是 macOS 锁屏播放录屏。

| 画作 | 作者 · 年代 | 动效与静止主体 | 快捷键 |
| --- | --- | --- | --- |
| 星空 | 文森特·梵高 · 1889 | 天空笔触流动；柏树、山丘与村庄静止。 | ⌘1 |
| 睡莲 | 克劳德·莫奈 · 1906 | 水面与倒影起伏；主要睡莲花簇静止。 | ⌘2 |
| 麦草堆：日落与雪景 | 克劳德·莫奈 · 1890–1891 | 暖色天空局部明暗变化；草堆、雪地与全部几何形状静止。 | ⌘3 |
| 罗讷河上的星夜 | 文森特·梵高 · 1888 | 河面与灯光倒影摇曳；岸线、船桅与人物静止。 | ⌘4 |
| 有柏树的麦田 | 文森特·梵高 · 1889 | 云层与麦浪流动；主要柏树和中间山丘静止。 | ⌘5 |
| 日出·印象 | 克劳德·莫奈 · 1872 | 水面与橙色倒影起伏；太阳、船只、人物与港口静止。 | ⌘6 |
| 滑铁卢桥：阳光效果 | 克劳德·莫奈 · 1903 | 河水与桥洞倒影微动；桥体与城市轮廓静止。 | ⌘7 |
| 蓝与银的夜曲：博格诺 | 詹姆斯·麦克尼尔·惠斯勒 · 1871–1876 | 海面缓慢起伏；地平线、帆船、海岸人物与岸线静止。 | ⌘8 |
| 驶近威尼斯 | 约瑟夫·马洛德·威廉·特纳 · 1844 | 潟湖水面闪动；天空、城市、贡多拉与船桅静止。 | ⌘9 |
| 普维尔悬崖漫步 | 克劳德·莫奈 · 1882 | 云层、露出的海面与草叶分区流动；人物、阳伞、小路与崖壁静止。 | ⌘0 |
| 维尔纳夫拉加伦的桥 | 阿尔弗雷德·西斯莱 · 1872 | 局部河流与倒影流动；桥梁、船只、建筑与人物静止。 | ⌥⌘1 |
| 国会大厦，日落 | 克劳德·莫奈 · 1903 | 水面短横笔触微动；建筑、船、天空与签名静止。 | ⌥⌘2 |

每幅画都有独立的流场和主体遮罩。《麦草堆》只改变天空局部亮度，不移动画面几何，因此动效比水波和云层更轻微。

<details>
<summary>展开查看另外四幅画的独立动效预览</summary>

### 睡莲

![《睡莲》当前水面动效](docs/media/water-lilies.gif)

### 麦草堆：日落与雪景

![《麦草堆》当前天空明暗变化](docs/media/wheat-stacks.gif)

### 罗讷河上的星夜

![《罗讷河上的星夜》当前水面与倒影动效](docs/media/rhone.gif)

### 有柏树的麦田

![《有柏树的麦田》当前云层与麦浪动效](docs/media/cypresses.gif)

</details>

## 下载应用

需要 **搭载 Apple Silicon 的 Mac，以及 macOS 26**。

1. 到 [GitHub Releases](https://github.com/Rosemary1812/starry-night-wallpaper/releases) 下载 ZIP 安装包。
2. 解压，将 `Starry Night.app` 移入“应用程序”。
3. 打开应用。如果 macOS 阻止打开，在 Finder 中按住 Control 点击应用，再选择“打开”。

发布包附有 SHA-256 校验文件。目前已发布的 [v0.2.0](https://github.com/Rosemary1812/starry-night-wallpaper/releases/tag/v0.2.0) 使用之前的五幅画控制面板。本页的十二幅画画廊与预览媒体对应当前 `main` 分支。

这是使用 macOS 私有 API 的实验性扩展。构建使用 ad hoc 签名，未经过公证，也不面向 Mac App Store。后续 macOS 更新可能影响扩展兼容性。

## 设为壁纸

1. 打开应用，选择画作。
2. 点击“调整…”设置速度与强度。
3. 点击“设为壁纸”，等待渲染完成。
4. 如果系统没有切换壁纸，到 **系统设置 → 壁纸** 中选择 **StarryNight**。

首次使用时，先打开一次系统壁纸设置，让 macOS 初始化扩展。应用会为选定画作生成循环视频，再通知扩展读取新的渲染结果。

切换画作或调整滑块只更新预览。需要再次点击“设为壁纸”，系统壁纸才会更新。仅预览时不显示提示文字；渲染进度和已应用状态在需要时显示。

### 调整预览

| 控件 | 行为 |
| --- | --- |
| 速度 | 0.25× 至 2×。1× 时循环为 24 秒，0.25× 时为 96 秒，2× 时为 12 秒。 |
| 强度 | 0% 至 250%，默认 140%。0% 时关闭位移和动态明暗变化。 |
| 暂停预览 | 只暂停当前窗口中的动画，系统壁纸继续播放。 |
| 显示活动区域 | 临时标出预览中参与动画的区域。 |
| 语言 | 跟随系统、简体中文、繁體中文或 English。重启后保留选择。 |

画廊跟随 macOS 深浅色外观与“减少动态效果”设置。宽窗口将作品信息放在画作旁，窄窗口放在下方。应用在 Dock 中显示黑白图标。

### 导出视频

打开 **…** 菜单，选择“导出视频…”。应用按选定速度与强度，导出 30 fps 的 H.264 MP4 循环视频。输出宽度为 3840 像素，宽高比跟随主屏幕。导出不会更改当前壁纸。

“设为壁纸”使用 2560 像素宽度，同样跟随主屏幕宽高比。两种输出都会裁切画作以铺满画面，不拉伸原画。**…** 菜单还包含作品详情、来源许可与系统壁纸设置。

## 从源码构建当前版本

需要 macOS 26、Apple Silicon、Xcode Command Line Tools 和画作素材。应用与扩展使用 Swift、AppKit、Metal 和 AVFoundation。构建应用不需要 Python 或 FFmpeg。

```sh
git clone --branch main https://github.com/Rosemary1812/starry-night-wallpaper.git
cd starry-night-wallpaper
xcode-select --install
mkdir -p assets
```

如果已经安装命令行工具，跳过 `xcode-select --install`。

将可合法使用的《星空》复制图放到 `assets/starrynight.jpg`。可以使用 [Wikimedia Commons 上的公共领域复制图](https://commons.wikimedia.org/wiki/File:Van_Gogh_-_Starry_Night_-_Google_Art_Project.jpg)，下载缩小版本即可，不必使用体积很大的原始文件。

下载另外十一幅画作：

```sh
zsh scripts/fetch-artworks.sh
```

完整扩展构建还需要 `assets/starry-night-flow.mp4` 作为初始循环视频。如果没有这个文件，先构建控制面板，再用应用自己的渲染器生成：

```sh
STARRY_SKIP_EXTENSION_BUILD=1 zsh build.sh
"./Starry Night.app/Contents/MacOS/StarryNight" \
	--export "$PWD/assets/starry-night-flow.mp4" 2560 1600
zsh build.sh
open "Starry Night.app"
```

第一步生成预览应用；最后一次构建包含壁纸扩展，并为两个 bundle 签名。构建产物保存在仓库中，脚本不会安装应用或应用壁纸。

如果素材放在其他位置，在下载与构建前设置 `STARRY_ASSETS_DIR`。生成初始视频时，也将导出路径改为该目录中的 `starry-night-flow.mp4`。完整原图与视频不纳入 Git，文档中的缩小媒体会随仓库提交。

### 使用命令行渲染

`--artwork` 使用画作图片的文件名，不含 `.jpg`。先创建 `dist/`，再运行示例：

```sh
mkdir -p dist
"./Starry Night.app/Contents/MacOS/StarryNight" \
	--snapshot "$PWD/dist/rhone.png" 8 --artwork rhone
"./Starry Night.app/Contents/MacOS/StarryNight" \
	--export "$PWD/dist/rhone.mp4" 1920 1080 --artwork rhone
```

截图保留画作本身的宽高比。命令行视频导出使用速度 1×、强度 140%、24 秒循环，不会把视频发布到系统壁纸扩展。

## 常见问题

| 现象 | 处理方式 |
| --- | --- |
| 应用提示先打开系统壁纸设置。 | 打开一次 **系统设置 → 壁纸**，返回应用后再次点击“设为壁纸”。 |
| 渲染完成，桌面还是之前的壁纸。 | 在系统壁纸设置中选中 **StarryNight**。只修改预览不会更新桌面。 |
| 中间的画会动，旁边的画不动。 | 选中那幅画。只有选定并停稳的画作使用实时 Metal 预览。 |
| 某些动效不明显。 | 在“调整…”中提高强度。《麦草堆》只做轻微亮度变化，主体始终固定。 |
| 选择或操作按钮暂时不可用。 | 等待视频渲染完成，或等待画廊切换停稳。 |
| 构建提示缺少图片或初始视频。 | 检查 `assets/` 中的文件名，或 `STARRY_ASSETS_DIR` 指定的目录。 |

已应用状态表示系统设置中选中了该壁纸提供器，不代表每个显示器、空间或锁屏上的播放都经过验证。

## 验证与贡献

准备好源码素材后运行：

```sh
STARRY_VERIFY_EXPECTED_ARTWORK_COUNT=12 zsh scripts/verify-gallery.sh
```

脚本重新构建控制面板，检查本地化、画廊运动断言与 AppKit 布局，并验证十二幅画的 Metal 循环首尾、运动与主体保护采样点。证据保存在 `dist/gallery-evidence/` 与 `dist/evidence/`。采样点检查不能证明每个主体轮廓像素都固定不动。

检查可见窗口中的实时预览，以及最后一幅与第一幅之间的循环切换：

```sh
STARRY_VERIFY_LIVE_PREVIEW=1 \
	"./Starry Night.app/Contents/MacOS/StarryNight" \
	--ui-check "$PWD/dist/live-preview-evidence"
```

这项检查会打开窗口，确认每幅画都有完成的 GPU 帧。后台 AppKit 截图使用静态替代图，因为 `cacheDisplay` 无法捕获 Metal 展示层。这些检查不会应用壁纸，也不验证锁屏播放。

重新生成 README GIF，需要在 Python 环境中安装 Pillow：

```sh
python3 -m pip install Pillow
zsh scripts/record-readme-media.sh
```

如果 Pillow 安装在另一个解释器中，设置 `STARRY_PYTHON`。录制参数、媒体署名和输出尺寸见 [docs/media/README.md](docs/media/README.md)。

添加画作或修改动效前，先阅读 [画作动态壁纸创作技能](.agents/skills/author-painting-wallpaper/SKILL.md)。其中包含图像授权、主体遮罩、画廊接入与原生渲染证据要求。

### 代码位置

| 文件或目录 | 职责 |
| --- | --- |
| `Artwork.swift` | 画作 ID、文件名、裁切区域、年代与快捷键。 |
| `StarryNight.swift` 与 `Sky.metal` | 原生预览、遮罩、动效、视频导出与应用生命周期。 |
| `GalleryView.swift` 与 `CarouselMotion.swift` | 画廊绘制、控件、输入与无限滚动。 |
| `L10n.swift` 与三个 `.lproj` 目录 | 语言选择与本地化文本。 |
| `WallpaperBridge.swift` | 将渲染结果发布到扩展的本地视频库。 |
| `WallpaperExtension/` | 原生壁纸提供器与视频播放。 |
| `Icons/` 与 `Fonts/` | 应用图标与内置界面字体。 |
| `scripts/` | 构建、素材下载、录制与验证工具。 |

## 致谢与许可证

代码使用 MIT 许可。壁纸扩展派生自 [Phosphene](https://github.com/kageroumado/phosphene)，内置的 Adobe Source Serif 4 字体使用 SIL Open Font License。

画作复制图使用各自的许可。《滑铁卢桥》的复制图及其动画衍生内容保留 **CC BY-SA 4.0**，署名为 Claude Monet / Art Institute of Chicago，经 Wikimedia Commons 上传者 Maltaper 提供。十二幅画总览 GIF 包含该衍生内容。分发画作媒体前，请阅读 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。
