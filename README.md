# Mac图片与视频超分

[原版 SnowLeopard Vision](https://github.com/SnowLeopard-Elysia/SnowLeopard-Vision)（Windows）的 **macOS 原生重制版**。
原仓库只发布闭源应用，不含源码；本项目按照其公开功能与技术栈，从零实现了一套 Mac 版：

- **图片超分 / 视频超分 / 视频补帧 / 超分并补帧** 四种核心任务
- **原生 SwiftUI 界面**：拖放素材、四步流程（选素材 → 选任务 → 确认设置 → 跟踪结果）
- **Metal 加速**：通过 ncnn-vulkan（MoltenVK）调用 Apple 芯片 GPU
- **VideoToolbox 硬件编码**：H.264 / H.265 / Apple ProRes（替代 NVENC / AMF），支持 H.265 10-bit 输出
- **性能档位**：省电 / 均衡 / 极速（对应 ncnn 分块与线程参数）
- **任务链与磁盘优化**：中间帧用硬链接规范化命名，处理后自动清理，可选保留
- **进度与日志**：总进度 + 阶段进度实时呈现，失败时可复制日志、导出诊断信息
- **个性化**：六种主题色、浅色/深色/跟随系统

## 系统要求

- macOS 13.0（Ventura）及以上，Apple Silicon（M 系列）或 Intel
- [Homebrew](https://brew.sh)（用于安装 FFmpeg；也可手动放置）

## 安装依赖（首次使用）

1. 安装 FFmpeg：

```sh
brew install ffmpeg
```

2. 下载 ncnn 超分/补帧工具（Real-ESRGAN / Real-CUGAN / RIFE），脚本会自动匹配 macOS 版本并放到
   `~/Library/Application Support/SnowLeopardVision/bin`：

```sh
bash Scripts/install_deps.sh
```

> 若 GitHub 访问不畅，可到各工具的 Releases 手动下载 macOS 包，解压后把可执行文件与 `models*` 目录
> 一起放入上面的目录；或在应用「设置（⌘,）→ 工具路径」中手动指定。

## 构建与运行

```sh
swift run                # 开发运行
./Scripts/build_app.sh   # 打包为 build/SnowLeopardVision.app（release）
open build/SnowLeopardVision.app
```

## 使用说明

1. 把图片 / 视频 / 文件夹拖进第一张卡片（输出文件名自动生成）
2. 选择任务类型（四选一）
3. 确认设置：
   - 超分：Real-ESRGAN（通用）/ Real-CUGAN（二次元向，含降噪等级）/ Anime4K（实验性），2x–4x
   - 补帧：RIFE（默认 rife-v4.26），2x / 4x 帧率
   - 编码：VideoToolbox H.264 / H.265（支持 10-bit）/ ProRes；libx264 / libx265 软编（CRF）
   - 性能档位与 GPU 编号（Apple 内置显卡通常为 #0）
4. 点击「开始处理」，在底部跟踪总进度与当前阶段；完成后可「在访达中显示」

## 项目结构

```
Sources/SnowLeopardVision/
├── App/            应用入口、全局状态（AppModel）、主题
├── Core/           数据模型、日志、进程调度（ProcessRunner）、文件工具
├── Services/
│   ├── ToolLocator         依赖工具自动定位（应用内 / Homebrew / 用户目录 / PATH）
│   ├── DeviceService       芯片 / 内存 / GPU(Metal) 检测
│   ├── FFmpegProbe         ffprobe 媒体信息解析
│   ├── FFmpegFrames        抽帧与合成（-progress 解析进度）
│   ├── SuperResolution     Real-ESRGAN / Real-CUGAN / Anime4K 适配
│   ├── Interpolation       RIFE 补帧适配
│   └── PipelineService     任务流水线与阶段权重进度
└── Views/          SwiftUI 界面
Scripts/
├── install_deps.sh 依赖自动安装
└── build_app.sh    打包 .app
```

## 与 Windows 版的差异

| 项目 | Windows 版 | Mac 版（本项目） |
| --- | --- | --- |
| 图形加速 | Vulkan（NVIDIA/AMD/Intel） | Vulkan over MoltenVK（Apple Metal） |
| 硬件编码 | NVENC / AMF / QSV | VideoToolbox（H.264/HEVC/ProRes） |
| 界面 | （原版闭源） | SwiftUI 原生，支持拖放与系统外观 |
| 依赖分发 | 安装包内置 | Homebrew + 独立下载脚本（可打包进 .app） |

## Apple Silicon 兼容性适配说明

实测发现，官方 `realesrgan-ncnn-vulkan`（20210901 / 20220424 的 macOS 构建，arm64 与 Rosetta x86_64 均尝试）
在本机（Apple M4 / macOS 26）GPU 推理阶段必然段错误（退出码 139），而同家族的
`realcugan-ncnn-vulkan 20220728`、`rife-ncnn-vulkan 20221029`（更新的 ncnn 运行时）运行正常。

**原因**：旧版 ncnn 运行时与新 macOS 的 MoltenVK 图形栈不兼容；工具本体代码并无平台专属问题。

**适配方案**：Real-ESRGAN 后端改用 [upscayl/upscayl-ncnn](https://github.com/upscayl/upscayl-ncnn)
维护的 `upscayl-bin` 构建（基于新 ncnn，已实测在 M4 上正常推理）。它的模型文件格式与官方完全一致
（`models/{模型名}.param/.bin`，`realesr-animevideov3` 为 `-x倍数` 后缀），可直接复用官方模型。

应用内已做**双流派自动适配**：`SuperResolutionService` 会解析工具的 `-h` 输出，
识别是官方版还是 Upscayl 版，自动选择正确的参数组合（官方：`-n/-s/-m`；Upscayl：`-n/-m/-z/-s`）。
同样地，RIFE 参数也按官方 20221029 版语义适配（`-n` 为目标帧数、`-m` 为模型路径，
补帧倍数 4x 通过执行两遍实现）。

## 发布到 GitHub

仓库已包含 **GitHub Actions** 工作流，发布流程已自动化：

1. **首次推送**（建立仓库并上传代码）：
   ```sh
   # 在 GitHub 网站创建新仓库（例如：Mac-Vision），然后：
   git remote add origin git@github.com:你的用户名/Mac-Vision.git
   git push -u origin main
   ```

2. **触发自动 Release**（推送版本 tag）：
   ```sh
   git tag v1.0.0
   git push origin v1.0.0
   ```
   CI 会在 macOS 14 runner 上：
   - 安装全部依赖工具与模型（~700MB）
   - 编译 .app
   - 打包 DMG（含应用 + 全部 6 个工具 + 全部模型）
   - 上传到 GitHub Release 页面作为可下载资产

   用户下载 DMG 后拖入 `/Applications` 即可使用，**无需额外安装任何依赖**。

3. **本地手动打包**（不依赖 CI）：
   ```sh
   ./Scripts/make_release.sh    # 输出 release/Mac图片与视频超分-1.0.0-arm64.dmg
   ```

## 第三方组件声明

- **FFmpeg**：GNU LGPL 2.1+（含 GPL 组件的构建受 GPL 约束）
- **Real-ESRGAN / realesrgan-ncnn-vulkan**：BSD 3-Clause，版权归作者所有
- **Real-CUGAN / realcugan-ncnn-vulkan**、**Anime4K / Anime4KCPP**：版权归各自作者所有
- **RIFE / rife-ncnn-vulkan**：MIT（使用 ncnn 与源自 RIFE 项目的模型）

本应用只提供本地处理流程，不提供素材、不破解版权保护；请确保素材拥有合法的处理、导出与发布权限。
