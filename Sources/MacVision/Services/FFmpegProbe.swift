import Foundation

// MARK: - FFmpeg：媒体信息探测

struct FFmpegProbe {
    let tools: ToolSet
    let log: LogStore

    func probe(_ file: URL) async throws -> MediaInfo {
        guard let ffprobe = tools.ffprobe else {
            throw PipelineError.missingTool(.ffprobe)
        }
        let (status, output) = try await ProcessRunner.capture(
            executable: ffprobe.path,
            arguments: ["-v", "error", "-print_format", "json",
                        "-show_streams", "-show_format", file.path]
        )
        guard status == 0, let data = output.data(using: .utf8) else {
            throw PipelineError.probeFailed(file.lastPathComponent, output)
        }

        let decoded = try JSONDecoder().decode(FFProbeOutput.self, from: data)
        let streams = decoded.streams ?? []
        guard let video = streams.first(where: { $0.codec_type == "video" }) else {
            throw PipelineError.probeFailed(file.lastPathComponent, "未找到视频/图片流")
        }

        var info = MediaInfo()
        info.width = video.width ?? 0
        info.height = video.height ?? 0
        info.pixelFormat = video.pix_fmt
        info.videoCodec = video.codec_name
        info.frameRate = FFmpegProbe.parseRational(video.avg_frame_rate)
            ?? FFmpegProbe.parseRational(video.r_frame_rate)
            ?? 30
        info.duration = Double(decoded.format?.duration ?? "") ?? 0

        if let framesText = video.nb_frames, let frames = Int(framesText), frames > 0 {
            info.frameCount = frames
        } else if info.duration > 0, info.frameRate > 0 {
            info.frameCount = Int((info.duration * info.frameRate).rounded())
        }

        info.hasAudio = streams.contains { $0.codec_type == "audio" }
        return info
    }

    static func parseRational(_ text: String?) -> Double? {
        guard let text, !text.isEmpty, text != "0/0", text != "N/A" else { return nil }
        let parts = text.split(separator: "/").compactMap { Double($0) }
        guard parts.count == 2, parts[1] != 0 else { return Double(text) }
        return parts[0] / parts[1]
    }
}

private struct FFProbeOutput: Decodable {
    struct Stream: Decodable {
        let codec_type: String?
        let codec_name: String?
        let width: Int?
        let height: Int?
        let pix_fmt: String?
        let r_frame_rate: String?
        let avg_frame_rate: String?
        let nb_frames: String?
    }
    struct Format: Decodable {
        let duration: String?
    }
    let streams: [Stream]?
    let format: Format?
}
