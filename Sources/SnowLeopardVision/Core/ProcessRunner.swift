import Foundation

// MARK: - 进程运行器（异步封装 Process，合并 stdout/stderr，支持取消）

struct ProcessRunner {

    /// 运行命令并逐行回调输出。返回退出码。
    @discardableResult
    static func run(executable: String,
                    arguments: [String],
                    extraEnvironment: [String: String] = [:],
                    token: CancellationToken? = nil,
                    onLine: (@Sendable (String) -> Void)? = nil) async throws -> Int32 {

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in extraEnvironment { environment[key] = value }
        process.environment = environment
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // 先启动读取任务，避免子进程写满管道缓冲导致死锁
        let readerTask = Task.detached(priority: .utility) {
            await pump(pipe: pipe, onLine: onLine)
        }

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ProcessError.launchFailed(
                    "无法启动 \(executable)：\(error.localizedDescription)\n请先在「环境检测」页确认依赖已安装。"
                ))
            }
            token?.attach(process)
        }

        await readerTask.value
        return status
    }

    /// 运行命令并收集完整输出。
    static func capture(executable: String,
                        arguments: [String],
                        token: CancellationToken? = nil) async throws -> (status: Int32, output: String) {
        let collector = LineCollector()
        let status = try await run(executable: executable,
                                   arguments: arguments,
                                   token: token) { line in
            collector.append(line)
        }
        return (status, collector.value)
    }

    /// 运行命令，非零退出时抛出错误。
    static func runOrThrow(executable: String,
                           arguments: [String],
                           token: CancellationToken? = nil,
                           onLine: (@Sendable (String) -> Void)? = nil) async throws {
        if token?.isCancelled == true { throw CancellationError() }
        let collector = LineCollector()
        let status = try await run(executable: executable,
                                   arguments: arguments,
                                   token: token) { line in
            collector.append(line)
            onLine?(line)
        }
        if token?.isCancelled == true { throw CancellationError() }
        if status != 0 {
            throw ProcessError.nonZeroExit(
                (executable as NSString).lastPathComponent + " " + arguments.joined(separator: " "),
                status,
                collector.value
            )
        }
    }

    private static func pump(pipe: Pipe, onLine: (@Sendable (String) -> Void)?) async {
        var buffer = [UInt8]()
        buffer.reserveCapacity(4096)

        func flush() {
            guard !buffer.isEmpty else { return }
            let text = String(decoding: buffer, as: UTF8.self)
            buffer.removeAll(keepingCapacity: true)
            onLine?(text)
        }

        do {
            for try await byte in pipe.fileHandleForReading.bytes {
                if byte == 0x0A || byte == 0x0D {
                    flush()
                } else {
                    buffer.append(byte)
                }
            }
        } catch {
            // 管道被关闭属正常情况
        }
        flush()
    }
}
