import Foundation

// MARK: - 文件与目录辅助

enum FileTools {

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "bmp", "tga"]

    static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "flv", "wmv", "webm",
        "ts", "m2ts", "mts", "mpg", "mpeg", "vob", "3gp", "ogv"
    ]

    static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    static func isVideo(_ url: URL) -> Bool {
        videoExtensions.contains(url.pathExtension.lowercased())
    }

    /// 列出目录中的帧文件（按文件名排序，跳过隐藏文件）
    static func frameURLs(in directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        )) ?? []
        return contents
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .filter { isImage($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func countFrames(in directory: URL) -> Int {
        frameURLs(in: directory).count
    }

    /// 将目录中的帧规范化为 %08d.ext 连续命名（使用硬链接，避免复制占用磁盘）。
    /// 若目录本身已符合命名要求，则原样返回。
    static func normalizeFrames(_ directory: URL, into target: URL) throws -> URL {
        let urls = frameURLs(in: directory)
        guard !urls.isEmpty else { return directory }

        let expectedNames = urls.enumerated().map { item in
            String(format: "%08d.%@", item.offset, item.element.pathExtension.lowercased())
        }
        let actualNames = urls.map { $0.lastPathComponent }
        if actualNames == expectedNames { return directory }

        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for (index, source) in urls.enumerated() {
            let destination = target.appendingPathComponent(expectedNames[index])
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            do {
                try FileManager.default.linkItem(at: source, to: destination)
            } catch {
                try FileManager.default.copyItem(at: source, to: destination)
            }
        }
        return target
    }

    static func removeItemIfPossible(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func makeUniqueDirectory(root: URL, prefix: String) throws -> URL {
        let directory = root.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func makeDirectoryIfMissing(_ url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// 将拖入的 URL 展开为可处理的素材列表（目录则收集其中的图片/视频）
    static func expandInputs(_ urls: [URL]) -> [InputItem] {
        var result: [InputItem] = []
        var seen = Set<String>()

        func add(_ url: URL) {
            guard !seen.contains(url.standardizedFileURL.path) else { return }
            seen.insert(url.standardizedFileURL.path)
            result.append(InputItem(url: url))
        }

        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let contents = (try? FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: []
                )) ?? []
                let media = contents
                    .filter { !$0.lastPathComponent.hasPrefix(".") }
                    .filter { isImage($0) || isVideo($0) }
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                media.forEach(add)
            } else if isImage(url) || isVideo(url) {
                add(url)
            }
        }
        return result.sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
    }

    /// 生成不与现有文件冲突的输出路径（name (2).ext）
    static func nonConflictingURL(for url: URL) -> URL {
        var candidate = url
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let base = url.deletingPathExtension().lastPathComponent
            candidate = url.deletingLastPathComponent()
                .appendingPathComponent("\(base) (\(counter)).\(url.pathExtension)")
            counter += 1
        }
        return candidate
    }
}

extension String {
    func shellSplitArguments() -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        for character in self {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty { result.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

// MARK: - 工具相对路径解析

extension FileTools {
    /// ncnn 工具的模型目录位于可执行文件旁；将裸模型名解析为绝对路径
    static func resolveToolRelativePath(executable: URL, name: String) -> String {
        let candidate = executable.deletingLastPathComponent().appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate.path
        }
        return name
    }
}

// MARK: - 数组子序列替换

extension Array where Element: Equatable {
    /// 将首个出现的子序列替换为新序列（用于调整 ffmpeg 参数）
    func replacingFirstSubsequence(_ target: [Element], with replacement: [Element]) -> [Element] {
        guard !target.isEmpty, target.count <= count else { return self }
        for start in 0...(count - target.count) {
            if Array(self[start..<(start + target.count)]) == target {
                var result = Array(self[0..<start])
                result.append(contentsOf: replacement)
                result.append(contentsOf: self[(start + target.count)...])
                return result
            }
        }
        return self
    }
}
