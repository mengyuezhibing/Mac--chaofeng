# Mac图片与视频超分

一个完全本地运行的 **macOS 原生 AI 图片 / 视频增强工具**，用 SwiftUI 从零编写。
所有处理都在本机完成，不联网、不上传素材。

## 功能

- **四种任务**：图片超分、视频超分、视频补帧、超分并补帧
- **拖放即用**：把图片 / 视频 / 文件夹拖进窗口即可，输出文件名自动生成
- **GPU 加速推理**：通过 ncnn-vulkan（MoltenVK）调用 Apple 芯片 GPU，实时显示正在使用的设备
- **硬件编码输出**：VideoToolbox H.264 / H.265 / Apple ProRes，支持 H.265 10-bit
- **性能档位**：省电 / 均衡 / 极速（对应 ncnn 分块与线程参数）
- **长视频友好**：中间帧用硬链接规范化命名，任务结束自动清理，可选保留
- **进度透明**：总进度 + 阶段进度实时呈现，失败可复制日志或导出诊断信息
- **外观个性化**：六种主题色、浅色 / 深色 / 跟随系统

## 系统要求

- macOS 13.0（Ventura）及以上
- Apple Silicon（M 系列）或 Intel
- 依赖 FFmpeg 与 ncnn 系列命令行工具（首次运行会自动检测并给出安装指引）

## 快速开始

### 方式一：下载 DMG（推荐）

从 [Releases](../../releases) 下载 `Mac图片与视频超分-*.dmg`，拖入「应用程序」即可。
**DMG 已内置全部工具与全部模型，无需额外安装任何依赖。**

首次打开若提示「无法验证开发者」，请到
「系统设置 → 隐私与安全性」点击「仍要打开」（本项目为开源免费软件，未做开发者签名）。

### 方式二：从源码构建

```sh
# 1. 安装依赖（自动下载 FFmpeg、超分/补帧工具与模型）
bash Scripts/install_deps.sh

# 2. 编译并打包
./Scripts/build_app.sh release

# 3. 运行
open build/MacVision.app
```

依赖会安装到 `~/Library/Application Support/MacVision/bin`。
若网络不畅，可在应用「设置（⌘,）→ 工具路径」中手动指定已下载的工具路径。

## 使用说明

1. 把图片 / 视频 / 文件夹拖进第一张卡片
2. 选择任务类型（四选一）
3. 确认设置：
   - **超分**：Real-ESRGAN（通用）/ Real-CUGAN（二次元向，含降噪等级）/ Anime4K（实验性），2x–4x
   - **补帧**：RIFE（默认 rife-v4.6），2x / 4x 帧率
   - **编码**：VideoToolbox H.264 / H.265（支持 10-bit）/ ProRes；libx264 / libx265 软编（CRF）
   - **性能**：性能档位与 GPU 编号（Apple 内置显卡通常为 #0）
4. 点击「开始处理」，底部跟踪总进度与当前阶段；完成后可「在访达中显示」

## 项目结构

```
Sources/MacVision/
├── App/            应用入口、全局状态（AppModel）、主题、菜单栏
├── Core/           数据模型、日志、进程调度（ProcessRunner）、文件工具
├── Services/
│   ├── ToolLocator         依赖工具自动定位（应用内 / 用户目录 / Homebrew / PATH）
│   ├── DeviceService       芯片 / 内存 / GPU 检测
│   ├── FFmpegProbe         ffprobe 媒体信息解析
│   ├── FFmpegFrames        抽帧与合成（-progress 解析进度）
│   ├── SuperResolution     Real-ESRGAN / Real-CUGAN / Anime4K 适配
│   ├── Interpolation       RIFE 补帧适配
│   └── PipelineService     任务流水线与阶段权重进度
└── Views/          SwiftUI 界面
Resources/          应用图标与中文本地化资源
Scripts/
├── install_deps.sh  依赖自动安装
├── build_app.sh     打包 .app
└── make_release.sh  打包含全部模型的 DMG
```


## 自动构建与发布

仓库已包含 GitHub Actions 工作流：

- **CI**（`.github/workflows/ci.yml`）：每次 push / PR 自动编译并上传 .app 产物
- **Release**（`.github/workflows/release.yml`）：推送版本 tag 自动发布

```sh
git tag v1.0.0
git push origin v1.0.0
```

CI 会在 macOS 14 runner 上安装全部依赖与模型、编译 .app、打包 DMG，
并上传到 Release 页面作为可下载资产。

本地手动打包：

```sh
./Scripts/make_release.sh    # 输出 release/Mac图片与视频超分-<version>-arm64.dmg
```

## 开源协议

本应用代码以 **MIT** 协议发布（见 [LICENSE](LICENSE)）。

调用的第三方命令行工具版权归各自作者所有，其许可如下：

- **FFmpeg / FFprobe**：GNU LGPL 2.1+（含 GPL 组件的构建受 GPL 约束）
- **Real-ESRGAN / realesrgan-ncnn-vulkan**：BSD 3-Clause
- **Real-CUGAN / realcugan-ncnn-vulkan**：BSD 3-Clause
- **Anime4K / Anime4KCPP**：MIT
- **RIFE / rife-ncnn-vulkan**：MIT（使用 ncnn 与源自 RIFE 项目的模型）

本应用只提供本地处理流程，不提供素材、不破解版权保护、不内置影视资源。
请确保输入素材拥有合法的处理、修改、导出与发布权限。
