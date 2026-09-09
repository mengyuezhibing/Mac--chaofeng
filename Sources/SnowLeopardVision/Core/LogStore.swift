import Foundation

// MARK: - 日志

enum LogLevel: String {
    case info
    case command
    case warn
    case error
    case success
}

struct LogLine: Identifiable {
    let id: UUID
    let date: Date
    let level: LogLevel
    let text: String

    init(level: LogLevel, text: String) {
        self.id = UUID()
        self.date = Date()
        self.level = level
        self.text = text
    }

    var renderedLine: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let prefix: String
        switch level {
        case .info: prefix = "[信息]"
        case .command: prefix = "[命令]"
        case .warn: prefix = "[警告]"
        case .error: prefix = "[错误]"
        case .success: prefix = "[完成]"
        }
        return "\(formatter.string(from: date)) \(prefix) \(text)"
    }
}

final class LogStore: ObservableObject {
    @Published private(set) var lines: [LogLine] = []

    private let maximumLines = 3000

    func append(_ text: String, level: LogLevel = .info) {
        let line = LogLine(level: level, text: text)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lines.append(line)
            if self.lines.count > self.maximumLines {
                self.lines.removeFirst(self.lines.count - self.maximumLines)
            }
        }
    }

    func clear() {
        DispatchQueue.main.async { [weak self] in self?.lines = [] }
    }

    var plainText: String {
        lines.map { $0.renderedLine }.joined(separator: "\n")
    }
}

// MARK: - 取消令牌

final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var currentProcess: Process?

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = currentProcess
        lock.unlock()
        process?.terminate()
    }

    func attach(_ process: Process) {
        lock.lock()
        currentProcess = process
        let shouldTerminate = cancelled
        lock.unlock()
        if shouldTerminate { process.terminate() }
    }
}

// MARK: - 输出收集器

final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    func append(_ text: String) {
        lock.lock()
        if buffer.count < 200_000 { buffer += text + "\n" }
        lock.unlock()
    }

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}

// MARK: - 进程错误

enum ProcessError: LocalizedError {
    case launchFailed(String)
    case nonZeroExit(String, Int32, String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return message
        case .nonZeroExit(let command, let code, let output):
            let tail = String(output.suffix(1500))
            return "命令执行失败（退出码 \(code)）：\(command)\n\(tail)"
        }
    }
}
