import Foundation

// MARK: - 任务类型

enum TaskKind: String, CaseIterable, Identifiable, Codable {
    case imageSuperResolution
    case videoSuperResolution
    case videoInterpolation
    case superResolutionAndInterpolation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .imageSuperResolution: return "图片超分"
        case .videoSuperResolution: return "视频超分"
        case .videoInterpolation: return "视频补帧"
        case .superResolutionAndInterpolation: return "超分并补帧"
        }
    }

    var symbol: String {
        switch self {
        case .imageSuperResolution: return "photo"
        case .videoSuperResolution: return "film"
        case .videoInterpolation: return "timelapse"
        case .superResolutionAndInterpolation: return "sparkles"
        }
    }

    var subtitle: String {
        switch self {
        case .imageSuperResolution: return "提高原图分辨率并增强可见细节"
        case .videoSuperResolution: return "逐帧增强画面后重新合成为高分辨率视频"
        case .videoInterpolation: return "用 RIFE 生成中间帧，提升画面流畅度"
        case .superResolutionAndInterpolation: return "先提升清晰度，再生成中间帧，一次完成"
        }
    }

    var needsSuperResolution: Bool { self != .videoInterpolation }
    var needsInterpolation: Bool {
        self == .videoInterpolation || self == .superResolutionAndInterpolation
    }
    var isImageTask: Bool { self == .imageSuperResolution }
}

// MARK: - 超分后端

enum SRBackend: String, CaseIterable, Identifiable, Codable {
    case realESRGAN
    case realCUGAN
    case anime4K

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .realESRGAN: return "Real-ESRGAN"
        case .realCUGAN: return "Real-CUGAN"
        case .anime4K: return "Anime4K（实验性）"
        }
    }

    var note: String {
        switch self {
        case .realESRGAN: return "通用与二次元插画均适用，速度快、兼容性最好"
        case .realCUGAN: return "二次元插画/动画细节更强，可选降噪等级"
        case .anime4K: return "需要本地具备 Anime4KCPP_CLI，参数以实际版本为准"
        }
    }

    var executableName: String {
        switch self {
        case .realESRGAN: return "realesrgan-ncnn-vulkan"
        case .realCUGAN: return "realcugan-ncnn-vulkan"
        case .anime4K: return "Anime4KCPP_CLI"
        }
    }

    var tool: ToolKind {
        switch self {
        case .realESRGAN: return .realesrgan
        case .realCUGAN: return .realcugan
        case .anime4K: return .anime4k
        }
    }

    /// 常用模型名，作为输入框建议
    var presetModels: [String] {
        switch self {
        case .realESRGAN:
            return [
                "realesr-animevideov3",
                "realesrgan-x4plus-anime",
                "realesrgan-x4plus",
                "realesrnet-x4plus"
            ]
        case .realCUGAN:
            return ["models-se", "models-pro", "models-nose"]
        case .anime4K:
            return ["acnet-f8b8-hdn", "acnet-f8b8-cbdn", "acnet-f8b4", "acnet-f8b4-hdn", "acnet-legacy-hdn3", "acnet-legacy-gan"]
        }
    }

    var defaultModel: String {
        switch self {
        case .realESRGAN: return "realesr-animevideov3"
        case .realCUGAN: return "models-se"
        case .anime4K: return "acnet-f8b8-hdn"
        }
    }

    var supportedScales: [Int] {
        switch self {
        case .realESRGAN: return [2, 3, 4]
        case .realCUGAN: return [1, 2, 3, 4]
        case .anime4K: return [2, 3, 4]
        }
    }

    /// 是否使用 `-n <模型名>`（Anime4KCPP 不支持）
    var usesModelFlag: Bool { self != .anime4K }
}

// MARK: - 补帧后端

enum InterpolationBackend: String, CaseIterable, Identifiable, Codable {
    case rife

    var id: String { rawValue }
    var displayName: String { "RIFE (rife-ncnn-vulkan)" }
    var executableName: String { "rife-ncnn-vulkan" }
    var presetModels: [String] {
        ["rife-v4.6", "rife-v4", "rife-v3.1", "rife-v2.4", "rife-UHD", "rife-HD", "rife-anime"]
    }
}

// MARK: - 视频编码器

enum VideoEncoder: String, CaseIterable, Identifiable, Codable {
    case h264VideoToolbox = "h264_videotoolbox"
    case hevcVideoToolbox = "hevc_videotoolbox"
    case proresVideoToolbox = "prores_videotoolbox"
    case h264Software = "libx264"
    case hevcSoftware = "libx265"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .h264VideoToolbox: return "H.264（VideoToolbox 硬件）"
        case .hevcVideoToolbox: return "H.265/HEVC（VideoToolbox 硬件）"
        case .proresVideoToolbox: return "Apple ProRes（VideoToolbox 硬件）"
        case .h264Software: return "H.264（libx264 软件）"
        case .hevcSoftware: return "H.265/HEVC（libx265 软件）"
        }
    }

    var isHardware: Bool { rawValue.contains("videotoolbox") }
    var isHEVC: Bool { rawValue.contains("hevc") || rawValue.contains("x265") }
    var supportsTenBit: Bool { self == .hevcVideoToolbox || self == .hevcSoftware }
    var usesBitrate: Bool { isHardware && self != .proresVideoToolbox }
    var usesCRF: Bool { !isHardware }
}

// MARK: - 性能档位

enum PerformanceTier: String, CaseIterable, Identifiable, Codable {
    case eco
    case balanced
    case turbo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .eco: return "省电（低占用）"
        case .balanced: return "均衡"
        case .turbo: return "极速"
        }
    }

    var note: String {
        switch self {
        case .eco: return "小分块 + 少线程，内存与功耗占用最低"
        case .balanced: return "自动分块，兼顾速度、占用与稳定性"
        case .turbo: return "自动分块 + 更多加载/保存线程，适合长视频"
        }
    }

    /// ncnn 的 -t 分块大小，0 表示自动
    var tileSize: Int {
        switch self {
        case .eco: return 256
        case .balanced: return 0
        case .turbo: return 0
        }
    }

    /// ncnn 的 -j load:proc:save
    var threadSpec: String {
        switch self {
        case .eco: return "1:2:2"
        case .balanced: return "1:2:2"
        case .turbo: return "2:4:4"
        }
    }
}

// MARK: - 中间帧格式

enum IntermediateFormat: String, CaseIterable, Identifiable, Codable {
    case png
    case jpg

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .png: return "PNG（无损，质量最好）"
        case .jpg: return "JPG（体积小，节省磁盘）"
        }
    }
    var fileExtension: String { rawValue }

    /// 抽帧时附加给 ffmpeg 的参数
    var extractArguments: [String] {
        switch self {
        case .png: return []
        case .jpg: return ["-qscale:v", "1"]
        }
    }
}

// MARK: - 输出图片格式

enum ImageOutputFormat: String, CaseIterable, Identifiable, Codable {
    case png, jpg, webp
    var id: String { rawValue }
    var displayName: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }
}

// MARK: - 媒体信息

struct MediaInfo {
    var width: Int = 0
    var height: Int = 0
    var frameRate: Double = 0
    var frameCount: Int = 0
    var duration: Double = 0
    var hasAudio: Bool = false
    var pixelFormat: String?
    var videoCodec: String?

    var summary: String {
        let size = width > 0 ? "\(width)×\(height)" : "未知分辨率"
        let fps = frameRate > 0 ? String(format: "%.3f fps", frameRate) : "未知帧率"
        let frames = frameCount > 0 ? "约 \(frameCount) 帧" : "帧数未知"
        let audio = hasAudio ? "含音频" : "无音频"
        return "\(size) · \(fps) · \(frames) · \(audio)"
    }
}

// MARK: - 任务配置（可在线程间传递）

struct JobSettings: Sendable {
    var task: TaskKind = .videoSuperResolution
    var backend: SRBackend = .realESRGAN
    var srModel: String = SRBackend.realESRGAN.defaultModel
    var scale: Int = 2
    var cuganNoise: Int = 3
    var extraSRArguments: String = ""
    var interpModel: String = "rife-v4.26"
    var fpsMultiplier: Int = 2
    var extraInterpArguments: String = ""
    var encoder: VideoEncoder = .h264VideoToolbox
    var bitrateMbps: Double = 20
    var crf: Int = 18
    var tenBitOutput: Bool = false
    var keepAudio: Bool = true
    var intermediateFormat: IntermediateFormat = .png
    var performance: PerformanceTier = .balanced
    var gpuIndex: Int = 0
    var keepIntermediateFiles: Bool = false
    var outputDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    var outputName: String = ""
    var imageOutputFormat: ImageOutputFormat = .png
    var tempRoot: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

    var outputContainerExtension: String { "mp4" }
}

// MARK: - 流水线状态

enum PipelineStage: String {
    case idle
    case preparing
    case probing
    case extracting
    case upscaling
    case interpolating
    case encoding
    case finished

    var label: String {
        switch self {
        case .idle: return "空闲"
        case .preparing: return "准备中"
        case .probing: return "分析素材"
        case .extracting: return "抽取帧"
        case .upscaling: return "AI 超分"
        case .interpolating: return "AI 补帧"
        case .encoding: return "合成输出"
        case .finished: return "完成"
        }
    }
}

struct PipelineStatus: Sendable {
    var stage: PipelineStage
    var label: String
    var detail: String
    var stageFraction: Double
    var overallFraction: Double
}

// MARK: - 输入项

struct InputItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let isDirectory: Bool
    let fileSize: Int64

    init(url: URL) {
        self.id = UUID()
        self.url = url
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        self.fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
