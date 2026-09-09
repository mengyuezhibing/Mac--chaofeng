import Foundation

enum PipelineError: LocalizedError {
    case missingTool(ToolKind)
    case probeFailed(String, String)
    case extractFailed(String)
    case unsupportedInput(String)

    var errorDescription: String? {
        switch self {
        case .missingTool(let kind):
            return "未找到依赖工具 \(kind.executableName)。请到「环境检测」页安装或手动指定路径。"
        case .probeFailed(let file, let detail):
            return "无法解析素材 \(file)：\(String(detail.suffix(600)))"
        case .extractFailed(let file):
            return "抽取帧失败：\(file)"
        case .unsupportedInput(let file):
            return "素材类型与当前任务不匹配：\(file)"
        }
    }
}
