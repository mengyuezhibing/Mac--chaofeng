import Foundation

// MARK: - 依赖工具定义

enum ToolKind: String, CaseIterable, Identifiable {
    case ffmpeg
    case ffprobe
    case realesrgan
    case realcugan
    case rife
    case anime4k

    var id: String { rawValue }

    var executableName: String {
        switch self {
        case .ffmpeg: return "ffmpeg"
        case .ffprobe: return "ffprobe"
        case .realesrgan: return "realesrgan-ncnn-vulkan"
        case .realcugan: return "realcugan-ncnn-vulkan"
        case .rife: return "rife-ncnn-vulkan"
        case .anime4k: return "Anime4KCPP_CLI"
        }
    }

    var displayName: String {
        switch self {
        case .ffmpeg: return "FFmpeg"
        case .ffprobe: return "FFprobe"
        case .realesrgan: return "Real-ESRGAN (ncnn-vulkan)"
        case .realcugan: return "Real-CUGAN (ncnn-vulkan)"
        case .rife: return "RIFE (ncnn-vulkan)"
        case .anime4k: return "Anime4KCPP CLI"
        }
    }

    var purpose: String {
        switch self {
        case .ffmpeg: return "视频抽帧、合成与硬件编码（必需）"
        case .ffprobe: return "读取视频信息（必需）"
        case .realesrgan: return "图片/视频超分（Real-ESRGAN 模型）"
        case .realcugan: return "二次元向超分（Real-CUGAN 模型）"
        case .rife: return "视频补帧"
        case .anime4k: return "动漫风格超分（实验性）"
        }
    }

    var isRequired: Bool { self == .ffmpeg || self == .ffprobe }

    /// Homebrew 可直接安装的名称
    var brewName: String? {
        switch self {
        case .ffmpeg, .ffprobe: return "ffmpeg"
        default: return nil
        }
    }

    /// 便于用户手动下载的 GitHub 仓库
    var repository: String? {
        switch self {
        case .realesrgan: return "xinntao/Real-ESRGAN"
        case .realcugan: return "nihui/realcugan-ncnn-vulkan"
        case .rife: return "TNTwise/rife-ncnn-vulkan"
        case .anime4k: return "TianZerL/Anime4KCPP"
        default: return nil
        }
    }
}

struct ToolStatus: Identifiable {
    let kind: ToolKind
    var path: String?
    var version: String?

    var id: String { kind.id }
    var found: Bool { path != nil }
}

// MARK: - 工具集合

struct ToolSet {
    var ffmpeg: URL?
    var ffprobe: URL?
    var realesrgan: URL?
    var realcugan: URL?
    var rife: URL?
    var anime4k: URL?

    func url(for kind: ToolKind) -> URL? {
        switch kind {
        case .ffmpeg: return ffmpeg
        case .ffprobe: return ffprobe
        case .realesrgan: return realesrgan
        case .realcugan: return realcugan
        case .rife: return rife
        case .anime4k: return anime4k
        }
    }

    func url(for backend: SRBackend) -> URL? { url(for: backend.tool) }

    var isCoreReady: Bool { ffmpeg != nil && ffprobe != nil }
}

// MARK: - 工具定位器

final class ToolLocator: ObservableObject {
    @Published private(set) var statuses: [ToolKind: ToolStatus] = [:]

    /// 用户在偏好设置中覆盖的路径（key 为 ToolKind.rawValue）
    var overrides: [String: String] = [:]

    private var cachedToolSet: ToolSet?

    /// 应用自带的 bin 目录（打包为 .app 时为 Contents/Resources/bin）
    static var bundledBinDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("bin", isDirectory: true)
    }

    /// 用户级工具目录
    static var applicationSupportBin: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("MacVision/bin", isDirectory: true)
    }

    func candidatePaths(for kind: ToolKind) -> [String] {
        let name = kind.executableName
        var directories: [String] = []

        if let override = overrides[kind.rawValue], !override.isEmpty {
            directories.append(override)
        }
        if let bundled = Self.bundledBinDirectory {
            directories.append(bundled.path)
        }
        directories.append(Self.applicationSupportBin.path)
        directories.append(contentsOf: [
            "/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin", "/bin"
        ])
        if let pathEnvironment = ProcessInfo.processInfo.environment["PATH"] {
            directories.append(contentsOf: pathEnvironment.split(separator: ":").map(String.init))
        }

        var candidates: [String] = []
        for directory in directories {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory)
            let full = exists && !isDirectory.boolValue
                ? directory
                : (directory as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: full) {
                candidates.append(full)
            }
        }
        return candidates
    }

    @MainActor
    func refresh() async {
        var result: [ToolKind: ToolStatus] = [:]
        for kind in ToolKind.allCases {
            guard let path = candidatePaths(for: kind).first else {
                result[kind] = ToolStatus(kind: kind, path: nil, version: nil)
                continue
            }
            let version = await Self.readVersion(executable: path, kind: kind)
            result[kind] = ToolStatus(kind: kind, path: path, version: version)
        }
        statuses = result
        cachedToolSet = ToolSet(
            ffmpeg: result[.ffmpeg]?.path.map { URL(fileURLWithPath: $0) },
            ffprobe: result[.ffprobe]?.path.map { URL(fileURLWithPath: $0) },
            realesrgan: result[.realesrgan]?.path.map { URL(fileURLWithPath: $0) },
            realcugan: result[.realcugan]?.path.map { URL(fileURLWithPath: $0) },
            rife: result[.rife]?.path.map { URL(fileURLWithPath: $0) },
            anime4k: result[.anime4k]?.path.map { URL(fileURLWithPath: $0) }
        )
    }

    var toolSet: ToolSet? { cachedToolSet }

    /// 读取工具版本（ncnn 工具用 -h，ffmpeg 系用 -version）
    static func readVersion(executable: String, kind: ToolKind) async -> String? {
        let arguments: [String]
        switch kind {
        case .ffmpeg, .ffprobe:
            arguments = ["-version"]
        default:
            arguments = ["-h"]
        }
        guard let result = try? await ProcessRunner.capture(executable: executable, arguments: arguments) else {
            return nil
        }
        let lines = result.output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return nil }
        return String(first.prefix(120))
    }
}
