import Foundation

// MARK: - 帧目录处理工具的公共运行器（ncnn-vulkan 系）

struct FrameToolRunner {
    let log: LogStore

    /// 运行处理目录帧的命令行工具，同时通过统计输出文件数量汇报进度
    func run(inputDirectory: URL,
             outputDirectory: URL,
             executable: URL,
             arguments: [String],
             label: String,
             expectedOutputFrames: Int,
             token: CancellationToken?,
             onProgress: @escaping @Sendable (Double) -> Void) async throws -> Int {
        try FileTools.makeDirectoryIfMissing(outputDirectory)

        var allArguments = ["-i", inputDirectory.path, "-o", outputDirectory.path]
        allArguments.append(contentsOf: arguments)

        log.append("\(label)：\(executable.lastPathComponent) \(allArguments.joined(separator: " "))",
                   level: .command)

        let monitorTask = Task.detached(priority: .utility) {
            await Self.monitor(directory: outputDirectory,
                               expected: max(expectedOutputFrames, 1),
                               token: token,
                               onProgress: onProgress)
        }
        defer { monitorTask.cancel() }

        do {
            try await ProcessRunner.runOrThrow(executable: executable.path,
                                               arguments: allArguments,
                                               token: token) { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { log.append(trimmed) }
            }
        } catch {
            monitorTask.cancel()
            throw error
        }

        if token?.isCancelled == true { throw CancellationError() }
        let produced = FileTools.countFrames(in: outputDirectory)
        onProgress(1)
        log.append("\(label) 完成，输出 \(produced) 帧", level: .success)
        return produced
    }

    /// 通过输出目录中的文件数量估算进度
    private static func monitor(directory: URL,
                                expected: Int,
                                token: CancellationToken?,
                                onProgress: @escaping @Sendable (Double) -> Void) async {
        while !(token?.isCancelled ?? false) && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 700_000_000)
            let count = FileTools.countFrames(in: directory)
            onProgress(min(0.98, Double(count) / Double(expected)))
        }
    }
}
