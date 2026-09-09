import Foundation

// MARK: - 任务流水线：探测 → 抽帧 → 超分 → 补帧 → 合成

struct PipelineService {
    let tools: ToolSet
    let log: LogStore

    func run(input: URL,
             settings: JobSettings,
             token: CancellationToken?,
             onStatus: @escaping @Sendable (PipelineStatus) -> Void) async throws -> URL {
        guard tools.isCoreReady else { throw PipelineError.missingTool(.ffmpeg) }

        let probe = FFmpegProbe(tools: tools, log: log)
        let frames = FFmpegFrames(tools: tools, log: log)
        let sr = SuperResolutionService(tools: tools, log: log)
        let interp = InterpolationService(tools: tools, log: log)

        try FileTools.makeDirectoryIfMissing(settings.outputDirectory)
        let tempRoot = try FileTools.makeUniqueDirectory(root: settings.tempRoot, prefix: "macvision")
        defer {
            if !settings.keepIntermediateFiles { FileTools.removeItemIfPossible(tempRoot) }
        }

        // 阶段权重
        var stages: [(PipelineStage, Double)] = [(.extracting, 0.15)]
        if settings.task.needsSuperResolution { stages.append((.upscaling, 0.6)) }
        if settings.task.needsInterpolation { stages.append((.interpolating, 0.45)) }
        stages.append((.encoding, 0.15))
        let totalWeight = stages.reduce(0) { $0 + $1.1 }

        var completedWeight = 0.0
        func makeStatus(_ stage: PipelineStage, _ detail: String, _ fraction: Double) -> PipelineStatus {
            let weight = stages.first { $0.0 == stage }?.1 ?? 0
            let overall = min(0.999, (completedWeight + max(0, min(fraction, 1)) * weight) / totalWeight)
            return PipelineStatus(stage: stage,
                                  label: stage.label,
                                  detail: detail,
                                  stageFraction: max(0, min(fraction, 1)),
                                  overallFraction: overall)
        }

        let outputURL = try Self.outputURL(for: input, settings: settings)
        log.append("开始处理：\(input.lastPathComponent)（\(settings.task.title)）", level: .info)

        // 图片任务：直接调用超分
        if settings.task.isImageTask {
            onStatus(makeStatus(.upscaling, input.lastPathComponent, 0.1))
            try await sr.upscaleImage(input: input,
                                      output: FileTools.nonConflictingURL(for: outputURL),
                                      settings: settings,
                                      token: token)
            onStatus(makeStatus(.finished, "输出：\(outputURL.lastPathComponent)", 1))
            return outputURL
        }

        guard FileTools.isVideo(input) else {
            throw PipelineError.unsupportedInput(input.lastPathComponent)
        }

        // 1. 分析素材
        onStatus(makeStatus(.probing, input.lastPathComponent, 0.2))
        let info = try await probe.probe(input)
        guard info.width > 0, info.height > 0, info.frameRate > 0 else {
            throw PipelineError.probeFailed(input.lastPathComponent, "缺少分辨率或帧率")
        }
        log.append("素材信息：\(info.summary)", level: .info)

        // 2. 抽帧
        let framesDirectory = tempRoot.appendingPathComponent("frames", isDirectory: true)
        let extracted = try await frames.extractFrames(from: input,
                                                       into: framesDirectory,
                                                       format: settings.intermediateFormat,
                                                       expectedFrames: max(info.frameCount, 1),
                                                       token: token) { fraction in
            onStatus(makeStatus(.extracting, "\(info.summary)", fraction))
        }
        completedWeight += (stages.first { $0.0 == .extracting }?.1 ?? 0)

        // 3. 超分（Anime4KCPP_CLI 不支持目录模式，单独走逐文件路径）
        var workDirectory = framesDirectory
        var multiplier = 1
        if settings.task.needsSuperResolution {
            let upscaled = tempRoot.appendingPathComponent("upscaled", isDirectory: true)
            let count: Int
            if settings.backend == .anime4K {
                count = try await sr.upscaleFramesPerFile(inputDirectory: framesDirectory,
                                                          outputDirectory: upscaled,
                                                          frameCount: extracted,
                                                          settings: settings,
                                                          token: token) { fraction in
                    onStatus(makeStatus(.upscaling, "目标 \(info.width * settings.scale)×\(info.height * settings.scale) · \(settings.srModel)", fraction))
                }
            } else {
                count = try await sr.upscaleFrames(inputDirectory: framesDirectory,
                                                   outputDirectory: upscaled,
                                                   frameCount: extracted,
                                                   settings: settings,
                                                   token: token) { fraction in
                    onStatus(makeStatus(.upscaling, "目标 \(info.width * settings.scale)×\(info.height * settings.scale)", fraction))
                }
            }
            guard count > 0 else { throw PipelineError.extractFailed("超分输出为空") }
            completedWeight += (stages.first { $0.0 == .upscaling }?.1 ?? 0)
            workDirectory = upscaled
        }

        // 4. 补帧
        if settings.task.needsInterpolation {
            let interpolated = tempRoot.appendingPathComponent("interpolated", isDirectory: true)
            let count = try await interp.interpolateFrames(inputDirectory: workDirectory,
                                                           outputDirectory: interpolated,
                                                           frameCount: FileTools.countFrames(in: workDirectory),
                                                           settings: settings,
                                                           token: token) { fraction in
                onStatus(makeStatus(.interpolating, "\(settings.fpsMultiplier)× 帧率", fraction))
            }
            guard count > 0 else { throw PipelineError.extractFailed("补帧输出为空") }
            completedWeight += (stages.first { $0.0 == .interpolating }?.1 ?? 0)
            workDirectory = interpolated
            multiplier = max(settings.fpsMultiplier, 2)
        }

        // 5. 规范化命名并合成
        let normalized = try FileTools.normalizeFrames(workDirectory,
                                                       into: tempRoot.appendingPathComponent("normalized", isDirectory: true))
        onStatus(makeStatus(.encoding, "\(settings.encoder.displayName)", 0))
        try await frames.encode(frames: normalized,
                                format: settings.intermediateFormat,
                                frameRate: info.frameRate * Double(multiplier),
                                source: input,
                                settings: settings,
                                output: FileTools.nonConflictingURL(for: outputURL),
                                token: token) { fraction in
            onStatus(makeStatus(.encoding, "\(settings.encoder.displayName)", fraction))
        }

        onStatus(makeStatus(.finished, "输出：\(outputURL.lastPathComponent)", 1))
        log.append("完成：\(outputURL.path)", level: .success)
        return outputURL
    }

    /// 计算输出文件 URL
    static func outputURL(for input: URL, settings: JobSettings) throws -> URL {
        let base = settings.outputName.isEmpty
            ? input.deletingPathExtension().lastPathComponent
            : settings.outputName

        let suffix: String
        switch settings.task {
        case .imageSuperResolution:
            suffix = "\(settings.backendShortTag)\(settings.scale)x"
        case .videoSuperResolution:
            suffix = "\(settings.backendShortTag)\(settings.scale)x"
        case .videoInterpolation:
            suffix = "rife\(settings.fpsMultiplier)x"
        case .superResolutionAndInterpolation:
            suffix = "\(settings.backendShortTag)\(settings.scale)x-rife\(settings.fpsMultiplier)x"
        }

        let extensionName = settings.task.isImageTask ? settings.imageOutputFormat.fileExtension : "mp4"
        let name = base.isEmpty ? "output-\(suffix)" : "\(base)_\(suffix)"
        return settings.outputDirectory.appendingPathComponent("\(name).\(extensionName)")
    }
}

extension JobSettings {
    var backendShortTag: String {
        switch backend {
        case .realESRGAN: return "esrgan"
        case .realCUGAN: return "cugan"
        case .anime4K: return "a4k"
        }
    }
}
