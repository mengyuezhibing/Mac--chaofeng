import Foundation

// MARK: - AI 补帧服务（RIFE）

struct InterpolationService {
    let tools: ToolSet
    let log: LogStore

    /// 对帧目录补帧（RIFE 默认输出 2 倍帧，4x 时执行两遍），返回输出帧数
    func interpolateFrames(inputDirectory: URL,
                           outputDirectory: URL,
                           frameCount: Int,
                           settings: JobSettings,
                           token: CancellationToken?,
                           onProgress: @escaping @Sendable (Double) -> Void) async throws -> Int {
        guard let rife = tools.rife else { throw PipelineError.missingTool(.rife) }

        let arguments = baseArguments(for: settings, executable: rife)
        let runner = FrameToolRunner(log: log)

        // 第一遍：N → 2N
        let firstPassDirectory = outputDirectory.appendingPathComponent("pass1", isDirectory: true)
        let firstCount = try await runner.run(inputDirectory: inputDirectory,
                                              outputDirectory: firstPassDirectory,
                                              executable: rife,
                                              arguments: arguments,
                                              label: "AI 补帧（1/2）",
                                              expectedOutputFrames: max(frameCount * 2 - 1, 1),
                                              token: token,
                                              onProgress: { fraction in
            onProgress(fraction * 0.5)
        })
        guard firstCount > 0 else { throw PipelineError.extractFailed("补帧输出为空") }

        // 只需 2x 时直接返回（最终命名规范化由流水线统一处理）
        if settings.fpsMultiplier <= 2 {
            onProgress(1)
            return firstCount
        }

        // 第二遍前先规范化命名，确保输入顺序稳定
        let midDirectory = try FileTools.normalizeFrames(firstPassDirectory,
                                                         into: outputDirectory.appendingPathComponent("mid", isDirectory: true))
        let secondPassDirectory = outputDirectory.appendingPathComponent("pass2", isDirectory: true)
        let secondCount = try await runner.run(inputDirectory: midDirectory,
                                               outputDirectory: secondPassDirectory,
                                               executable: rife,
                                               arguments: arguments,
                                               label: "AI 补帧（2/2）",
                                               expectedOutputFrames: max(FileTools.countFrames(in: midDirectory) * 2 - 1, 1),
                                               token: token,
                                               onProgress: { fraction in
            onProgress(0.5 + fraction * 0.5)
        })
        guard secondCount > 0 else { throw PipelineError.extractFailed("二次补帧输出为空") }
        onProgress(1)
        return secondCount
    }

    /// 组装 RIFE 参数（不含 -i/-o）
    /// 注意：官方 rife-ncnn-vulkan 中 `-n` 是目标帧数（默认 N*2，即 2 倍），
    /// 模型通过 `-m` 指定；若使用 TNTwise 分支（-n 为模型名），可在高级参数中覆盖。
    private func baseArguments(for settings: JobSettings, executable: URL) -> [String] {
        var arguments: [String] = []
        if !settings.interpModel.isEmpty {
            let modelPath = FileTools.resolveToolRelativePath(executable: executable,
                                                              name: settings.interpModel)
            arguments.append(contentsOf: ["-m", modelPath])
        }
        arguments.append(contentsOf: ["-g", String(settings.gpuIndex)])
        if settings.performance.tileSize > 0 {
            arguments.append(contentsOf: ["-t", String(settings.performance.tileSize)])
        }
        arguments.append(contentsOf: ["-j", settings.performance.threadSpec])
        arguments.append(contentsOf: settings.extraInterpArguments.shellSplitArguments())
        return arguments
    }
}
