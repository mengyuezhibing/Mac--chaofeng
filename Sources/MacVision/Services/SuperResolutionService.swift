import Foundation

// MARK: - AI 超分服务（Real-ESRGAN / Real-CUGAN / Anime4K）

struct SuperResolutionService {
    let tools: ToolSet
    let log: LogStore

    private let runner = FrameToolRunner(log: LogStore())

    /// 对单张图片超分，返回输出文件 URL
    func upscaleImage(input: URL,
                      output: URL,
                      settings: JobSettings,
                      token: CancellationToken?) async throws {
        guard let executable = tools.url(for: settings.backend) else {
            throw PipelineError.missingTool(settings.backend.tool)
        }
        var arguments = await baseArguments(for: settings, executable: executable)
        arguments.append(contentsOf: ["-f", output.pathExtension])

        log.append("图片超分：\(input.lastPathComponent) → \(output.lastPathComponent)", level: .command)
        try await ProcessRunner.runOrThrow(executable: executable.path,
                                           arguments: ["-i", input.path, "-o", output.path] + arguments,
                                           token: token) { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { log.append(trimmed) }
        }
        if token?.isCancelled == true { throw CancellationError() }
        log.append("图片超分完成：\(output.lastPathComponent)", level: .success)
    }

    /// 对帧目录整体超分，返回输出帧数
    func upscaleFrames(inputDirectory: URL,
                       outputDirectory: URL,
                       frameCount: Int,
                       settings: JobSettings,
                       token: CancellationToken?,
                       onProgress: @escaping @Sendable (Double) -> Void) async throws -> Int {
        guard let executable = tools.url(for: settings.backend) else {
            throw PipelineError.missingTool(settings.backend.tool)
        }
        let arguments = await baseArguments(for: settings, executable: executable)
        let runner = FrameToolRunner(log: log)
        return try await runner.run(inputDirectory: inputDirectory,
                                    outputDirectory: outputDirectory,
                                    executable: executable,
                                    arguments: arguments,
                                    label: "AI 超分",
                                    expectedOutputFrames: frameCount,
                                    token: token,
                                    onProgress: onProgress)
    }

    /// 组装各后端的基础参数（不含 -i/-o）
    private func baseArguments(for settings: JobSettings, executable: URL) async -> [String] {
        var arguments: [String] = []
        switch settings.backend {
        case .realESRGAN:
            if !settings.srModel.isEmpty {
                arguments.append(contentsOf: ["-n", settings.srModel])
            }
            if let modelsDirectory = Self.modelsDirectory(for: executable) {
                arguments.append(contentsOf: ["-m", modelsDirectory])
            }
            if await Self.isUpscaylFlavor(executable: executable) {
                arguments.append(contentsOf: ["-z", String(settings.scale)])
            }
            arguments.append(contentsOf: ["-s", String(settings.scale)])
        case .realCUGAN:
            if !settings.srModel.isEmpty {
                // Real-CUGAN 通过 -m 指定模型目录（models-se/pro/nose）
                if let executable = tools.realcugan {
                    let modelPath = FileTools.resolveToolRelativePath(executable: executable,
                                                                      name: settings.srModel)
                    arguments.append(contentsOf: ["-m", modelPath])
                } else {
                    arguments.append(contentsOf: ["-m", settings.srModel])
                }
            }
            arguments.append(contentsOf: ["-n", String(settings.cuganNoise)])
            arguments.append(contentsOf: ["-s", String(settings.scale)])
        case .anime4K:
            // Anime4KCPP_CLI v3.2 参数格式：-m 模型 -p opencl -d 设备 -f 倍数
            // 注意它不支持目录模式，调用方需用逐文件循环
            if !settings.srModel.isEmpty {
                arguments.append(contentsOf: ["-m", settings.srModel])
            }
            arguments.append(contentsOf: ["-p", "opencl", "-d", "0"])
            arguments.append(contentsOf: ["-f", String(Double(settings.scale))])
        }

        arguments.append(contentsOf: ["-g", String(settings.gpuIndex)])
        if settings.performance.tileSize > 0 {
            arguments.append(contentsOf: ["-t", String(settings.performance.tileSize)])
        }
        arguments.append(contentsOf: ["-j", settings.performance.threadSpec])
        arguments.append(contentsOf: settings.extraSRArguments.shellSplitArguments())
        return arguments
    }

    /// 对帧目录逐文件超分（Anime4KCPP_CLI 不支持目录模式）
    func upscaleFramesPerFile(inputDirectory: URL,
                              outputDirectory: URL,
                              frameCount: Int,
                              settings: JobSettings,
                              token: CancellationToken?,
                              onProgress: @escaping @Sendable (Double) -> Void) async throws -> Int {
        guard let executable = tools.url(for: settings.backend) else {
            throw PipelineError.missingTool(settings.backend.tool)
        }
        try FileTools.makeDirectoryIfMissing(outputDirectory)

        let inputs = FileTools.frameURLs(in: inputDirectory)
        guard !inputs.isEmpty else { throw PipelineError.extractFailed("输入帧目录为空") }
        let baseArgs = await baseArguments(for: settings, executable: executable)

        let total = inputs.count
        var processed = 0
        for input in inputs {
            if token?.isCancelled == true { throw CancellationError() }
            let output = outputDirectory.appendingPathComponent(input.lastPathComponent)
            log.append("Anime4K 超分：\(input.lastPathComponent)", level: .info)
            try await ProcessRunner.runOrThrow(
                executable: executable.path,
                arguments: ["-i", input.path, "-o", output.path] + baseArgs,
                token: token
            ) { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { log.append(t) }
            }
            processed += 1
            onProgress(Double(processed) / Double(total))
        }
        log.append("Anime4K 完成，输出 \(processed) 帧", level: .success)
        return processed
    }

    /// 判断是否为 Upscayl 流派（其 -h 中包含 -z 参数说明）
    private static func isUpscaylFlavor(executable: URL) async -> Bool {
        guard let result = try? await ProcessRunner.capture(executable: executable.path,
                                                            arguments: ["-h"]) else {
            return false
        }
        return result.output.contains("-z")
    }

    /// 工具旁的模型目录（models）绝对路径
    private static func modelsDirectory(for executable: URL) -> String? {
        let directory = executable.deletingLastPathComponent().appendingPathComponent("models")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return directory.path
    }
}
