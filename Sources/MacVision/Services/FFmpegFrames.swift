import Foundation

// MARK: - FFmpeg：抽帧与合成

struct FFmpegFrames {
    let tools: ToolSet
    let log: LogStore

    /// 从视频中抽取帧序列
    func extractFrames(from source: URL,
                       into directory: URL,
                       format: IntermediateFormat,
                       expectedFrames: Int,
                       token: CancellationToken?,
                       onProgress: @escaping @Sendable (Double) -> Void) async throws -> Int {
        guard let ffmpeg = tools.ffmpeg else { throw PipelineError.missingTool(.ffmpeg) }
        try FileTools.makeDirectoryIfMissing(directory)
        let pattern = directory.appendingPathComponent("%08d.\(format.fileExtension)").path

        var arguments = ffmpegBaseArguments()
        arguments.append(contentsOf: ["-i", source.path])
        arguments.append(contentsOf: ["-an", "-sn", "-dn", "-vsync", "0", "-start_number", "0"])
        arguments.append(contentsOf: format.extractArguments)
        arguments.append(contentsOf: ["-f", "image2", pattern])

        log.append("ffmpeg 抽帧：\(source.lastPathComponent) → \(directory.lastPathComponent)", level: .command)
        try await runProgressing(executable: ffmpeg.path,
                                 arguments: arguments,
                                 expected: max(expectedFrames, 1),
                                 token: token,
                                 onProgress: onProgress)

        let count = FileTools.countFrames(in: directory)
        guard count > 0 else { throw PipelineError.extractFailed(source.lastPathComponent) }
        return count
    }

    /// 将帧序列合成为视频
    func encode(frames directory: URL,
                format: IntermediateFormat,
                frameRate: Double,
                source: URL,
                settings: JobSettings,
                output: URL,
                token: CancellationToken?,
                onProgress: @escaping @Sendable (Double) -> Void) async throws {
        guard let ffmpeg = tools.ffmpeg else { throw PipelineError.missingTool(.ffmpeg) }

        let expectedFrames = max(FileTools.countFrames(in: directory), 1)
        let pattern = directory.appendingPathComponent("%08d.\(format.fileExtension)").path

        var arguments = ffmpegBaseArguments()
        arguments.append(contentsOf: ["-f", "image2",
                                      "-framerate", String(format: "%.6f", frameRate),
                                      "-start_number", "0",
                                      "-i", pattern])
        arguments.append(contentsOf: ["-i", source.path, "-map", "0:v:0"])
        if settings.keepAudio { arguments.append(contentsOf: ["-map", "1:a:0?"]) }

        arguments.append(contentsOf: ["-c:v", settings.encoder.rawValue])
        if settings.encoder.usesBitrate {
            let megabits = max(1, Int(settings.bitrateMbps.rounded()))
            arguments.append(contentsOf: ["-b:v", "\(megabits)M"])
        } else if settings.encoder.usesCRF {
            arguments.append(contentsOf: ["-crf", String(settings.crf)])
        }
        arguments.append(contentsOf: ["-pix_fmt",
                                      pixelFormat(for: settings.encoder,
                                                  tenBit: settings.tenBitOutput)])
        if settings.encoder.isHEVC { arguments.append(contentsOf: ["-tag:v", "hvc1"]) }
        if settings.keepAudio {
            arguments.append(contentsOf: ["-c:a", "copy"])
        } else {
            arguments.append(contentsOf: ["-an"])
        }
        arguments.append(contentsOf: ["-movflags", "+faststart", output.path])

        log.append("ffmpeg 合成：\(output.lastPathComponent)（\(settings.encoder.displayName)）",
                   level: .command)

        do {
            try await runProgressing(executable: ffmpeg.path,
                                     arguments: arguments,
                                     expected: expectedFrames,
                                     token: token,
                                     onProgress: onProgress)
        } catch let error as ProcessError {
            guard settings.keepAudio, case .nonZeroExit = error else { throw error }
            log.append("音频直接封装失败，改用 AAC 192k 重试", level: .warn)
            let fallback = arguments.replacingFirstSubsequence(["-c:a", "copy"],
                                                               with: ["-c:a", "aac", "-b:a", "192k"])
            try await runProgressing(executable: ffmpeg.path,
                                     arguments: fallback,
                                     expected: expectedFrames,
                                     token: token,
                                     onProgress: onProgress)
        }
    }

    // MARK: 私有

    private func ffmpegBaseArguments() -> [String] {
        ["-y", "-hide_banner", "-nostdin", "-loglevel", "error",
         "-nostats", "-progress", "pipe:1"]
    }

    private func pixelFormat(for encoder: VideoEncoder, tenBit: Bool) -> String {
        if encoder == .proresVideoToolbox { return "yuv422p10le" }
        if tenBit && encoder.supportsTenBit { return "p010le" }
        return "yuv420p"
    }

    /// 运行 ffmpeg 并解析 `-progress pipe:1` 输出为进度
    private func runProgressing(executable: String,
                                arguments: [String],
                                expected: Int,
                                token: CancellationToken?,
                                onProgress: @escaping @Sendable (Double) -> Void) async throws {
        try await ProcessRunner.runOrThrow(executable: executable,
                                           arguments: arguments,
                                           token: token) { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("frame=") else { return }
            let numberText = trimmed.dropFirst("frame=".count)
                .trimmingCharacters(in: CharacterSet(charactersIn: " ="))
            guard let frame = Int(numberText) else { return }
            onProgress(min(0.999, Double(frame) / Double(expected)))
        }
    }
}
