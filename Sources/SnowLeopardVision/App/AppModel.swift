import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 全局应用状态

@MainActor
final class AppModel: ObservableObject {
    private let defaults = UserDefaults.standard

    // MARK: 输入
    @Published var inputs: [InputItem] = []
    @Published var isDropTargeted = false

    // MARK: 任务参数
    @Published var task: TaskKind { didSet { defaults.set(task.rawValue, forKey: "task") } }
    @Published var backend: SRBackend { didSet { defaults.set(backend.rawValue, forKey: "backend") } }
    @Published var srModel: String { didSet { defaults.set(srModel, forKey: "srModel") } }
    @Published var scale: Int { didSet { defaults.set(scale, forKey: "scale") } }
    @Published var cuganNoise: Int { didSet { defaults.set(cuganNoise, forKey: "cuganNoise") } }
    @Published var extraSRArguments: String { didSet { defaults.set(extraSRArguments, forKey: "extraSR") } }
    @Published var interpModel: String { didSet { defaults.set(interpModel, forKey: "interpModel") } }
    @Published var fpsMultiplier: Int { didSet { defaults.set(fpsMultiplier, forKey: "fpsMultiplier") } }
    @Published var extraInterpArguments: String { didSet { defaults.set(extraInterpArguments, forKey: "extraInterp") } }
    @Published var encoder: VideoEncoder { didSet { defaults.set(encoder.rawValue, forKey: "encoder") } }
    @Published var bitrateMbps: Double { didSet { defaults.set(bitrateMbps, forKey: "bitrate") } }
    @Published var crf: Int { didSet { defaults.set(crf, forKey: "crf") } }
    @Published var tenBitOutput: Bool { didSet { defaults.set(tenBitOutput, forKey: "tenBit") } }
    @Published var keepAudio: Bool { didSet { defaults.set(keepAudio, forKey: "keepAudio") } }
    @Published var intermediateFormat: IntermediateFormat { didSet { defaults.set(intermediateFormat.rawValue, forKey: "interFormat") } }
    @Published var performance: PerformanceTier { didSet { defaults.set(performance.rawValue, forKey: "performance") } }
    @Published var gpuIndex: Int { didSet { defaults.set(gpuIndex, forKey: "gpuIndex") } }
    @Published var keepIntermediateFiles: Bool { didSet { defaults.set(keepIntermediateFiles, forKey: "keepTemp") } }
    @Published var imageOutputFormat: ImageOutputFormat { didSet { defaults.set(imageOutputFormat.rawValue, forKey: "imgFormat") } }
    @Published var outputDirectory: URL { didSet { defaults.set(outputDirectory.path, forKey: "outDir") } }
    @Published var outputName: String { didSet { defaults.set(outputName, forKey: "outName") } }

    // MARK: 界面偏好
    @Published var accentColorName: String { didSet { defaults.set(accentColorName, forKey: "accent") } }
    @Published var appearanceRaw: String { didSet { defaults.set(appearanceRaw, forKey: "appearance") } }
    @Published var toolOverrides: [String: String] { didSet { defaults.set(toolOverrides, forKey: "toolOverrides") } }

    // MARK: 运行状态
    @Published private(set) var isRunning = false
    @Published private(set) var status = PipelineStatus(stage: .idle, label: "空闲", detail: "", stageFraction: 0, overallFraction: 0)
    @Published private(set) var outputs: [URL] = []
    @Published var errorMessage: String?
    @Published var showEnvironmentAlert = false

    let log = LogStore()
    let toolLocator = ToolLocator()
    private var token: CancellationToken?
    private var machineInfo: MachineInfo?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.task = TaskKind(rawValue: defaults.string(forKey: "task") ?? "") ?? .videoSuperResolution
        self.backend = SRBackend(rawValue: defaults.string(forKey: "backend") ?? "") ?? .realESRGAN
        self.srModel = defaults.string(forKey: "srModel") ?? SRBackend.realESRGAN.defaultModel
        self.scale = defaults.object(forKey: "scale") as? Int ?? 2
        self.cuganNoise = defaults.object(forKey: "cuganNoise") as? Int ?? 3
        self.extraSRArguments = defaults.string(forKey: "extraSR") ?? ""
        self.interpModel = defaults.string(forKey: "interpModel") ?? "rife-v4.6"
        self.fpsMultiplier = defaults.object(forKey: "fpsMultiplier") as? Int ?? 2
        self.extraInterpArguments = defaults.string(forKey: "extraInterp") ?? ""
        self.encoder = VideoEncoder(rawValue: defaults.string(forKey: "encoder") ?? "") ?? .h264VideoToolbox
        self.bitrateMbps = defaults.object(forKey: "bitrate") as? Double ?? 20
        self.crf = defaults.object(forKey: "crf") as? Int ?? 18
        self.tenBitOutput = defaults.bool(forKey: "tenBit")
        self.keepAudio = defaults.object(forKey: "keepAudio") as? Bool ?? true
        self.intermediateFormat = IntermediateFormat(rawValue: defaults.string(forKey: "interFormat") ?? "") ?? .png
        self.performance = PerformanceTier(rawValue: defaults.string(forKey: "performance") ?? "") ?? .balanced
        self.gpuIndex = defaults.object(forKey: "gpuIndex") as? Int ?? 0
        self.keepIntermediateFiles = defaults.bool(forKey: "keepTemp")
        self.imageOutputFormat = ImageOutputFormat(rawValue: defaults.string(forKey: "imgFormat") ?? "") ?? .png
        let savedDir = defaults.string(forKey: "outDir")
        self.outputDirectory = savedDir.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent("Desktop/SnowLeopardVision Output", isDirectory: true)
        self.outputName = defaults.string(forKey: "outName") ?? ""
        self.accentColorName = defaults.string(forKey: "accent") ?? "leopard"
        self.appearanceRaw = defaults.string(forKey: "appearance") ?? "system"
        self.toolOverrides = (defaults.dictionary(forKey: "toolOverrides") as? [String: String]) ?? [:]
        self.toolLocator.overrides = toolOverrides
    }

    // MARK: 派生值

    var accentColor: Color { ThemeColor.color(named: accentColorName) }

    var settings: JobSettings {
        JobSettings(task: task,
                    backend: backend,
                    srModel: srModel,
                    scale: scale,
                    cuganNoise: cuganNoise,
                    extraSRArguments: extraSRArguments,
                    interpModel: interpModel,
                    fpsMultiplier: fpsMultiplier,
                    extraInterpArguments: extraInterpArguments,
                    encoder: encoder,
                    bitrateMbps: bitrateMbps,
                    crf: crf,
                    tenBitOutput: tenBitOutput,
                    keepAudio: keepAudio,
                    intermediateFormat: intermediateFormat,
                    performance: performance,
                    gpuIndex: gpuIndex,
                    keepIntermediateFiles: keepIntermediateFiles,
                    outputDirectory: outputDirectory,
                    outputName: outputName,
                    imageOutputFormat: imageOutputFormat,
                    tempRoot: Self.defaultTempRoot)
    }

    static var defaultTempRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("SnowLeopardVision/Temp", isDirectory: true)
    }

    // MARK: 环境检测

    func refreshEnvironment() async {
        toolLocator.overrides = toolOverrides
        await toolLocator.refresh()
        machineInfo = await DeviceService.probeMachineInfo()
        log.append("环境检测完成", level: .info)
    }

    // MARK: 素材管理

    func addURLs(_ urls: [URL]) {
        let expanded = FileTools.expandInputs(urls)
        inputs.append(contentsOf: expanded.filter { item in
            !inputs.contains { $0.url.standardizedFileURL == item.url.standardizedFileURL }
        })
        if outputName.isEmpty, let first = inputs.first {
            outputName = first.url.deletingPathExtension().lastPathComponent
        }
    }

    func removeInput(_ item: InputItem) {
        inputs.removeAll { $0.id == item.id }
    }

    /// 处理拖放的 NSItemProvider
    nonisolated func handleDrop(_ providers: [NSItemProvider]) {
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await Self.fileURL(from: provider) {
                    urls.append(url)
                }
            }
            guard !urls.isEmpty else { return }
            addURLs(urls)
        }
    }

    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier,
                                  options: nil) { item, _ in
                if let data = item as? Data {
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func clearInputs() {
        inputs = []
        outputName = ""
    }

    // MARK: 运行

    var canStart: Bool {
        !isRunning && !inputs.isEmpty
    }

    func start() {
        guard canStart else { return }
        guard let toolSet = toolLocator.toolSet, toolSet.isCoreReady else {
            showEnvironmentAlert = true
            return
        }
        let currentSettings = settings
        let pendingInputs = inputs
        let pipeline = PipelineService(tools: toolSet, log: log)
        let cancelToken = CancellationToken()
        token = cancelToken
        isRunning = true
        outputs = []
        errorMessage = nil
        status = PipelineStatus(stage: .preparing, label: "准备中", detail: "", stageFraction: 0, overallFraction: 0)

        Task {
            var results: [URL] = []
            var failure: String?
            for input in pendingInputs {
                do {
                    let output = try await pipeline.run(input: input.url,
                                                        settings: currentSettings,
                                                        token: cancelToken) { newStatus in
                        Task { @MainActor [weak self] in self?.status = newStatus }
                    }
                    results.append(output)
                } catch is CancellationError {
                    log.append("任务已取消", level: .warn)
                    break
                } catch {
                    failure = error.localizedDescription
                    log.append(error.localizedDescription, level: .error)
                    break
                }
            }
            self.outputs = results
            self.isRunning = false
            self.token = nil
            if failure != nil {
                self.errorMessage = failure
                self.status = PipelineStatus(stage: .idle, label: "失败",
                                             detail: failure ?? "", stageFraction: 0, overallFraction: 0)
            } else if cancelToken.isCancelled {
                self.status = PipelineStatus(stage: .idle, label: "已取消", detail: "", stageFraction: 0, overallFraction: 0)
            } else {
                self.status = PipelineStatus(stage: .finished, label: "全部完成",
                                             detail: "共输出 \(results.count) 个文件", stageFraction: 1, overallFraction: 1)
            }
        }
    }

    func cancel() {
        token?.cancel()
        status.label = "正在取消…"
    }

    // MARK: 选择器

    func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.message = "选择图片、视频或文件夹"
        if panel.runModal() == .OK {
            addURLs(panel.urls)
        }
    }

    func pickOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "选择输出目录"
        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
        }
    }

    func revealOutput(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
