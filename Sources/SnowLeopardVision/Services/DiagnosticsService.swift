import Foundation

// MARK: - 诊断信息导出

enum DiagnosticsService {

    @MainActor
    static func buildReport(appModel: AppModel, machine: MachineInfo?) -> String {
        var lines: [String] = []
        lines.append("SnowLeopard Vision for Mac — 诊断信息")
        lines.append("生成时间：\(Date().formatted())")
        lines.append("")
        lines.append("== 设备 ==")
        if let machine { lines.append(machine.summary) }
        lines.append("")
        lines.append("== 依赖工具 ==")
        for kind in ToolKind.allCases {
            if let status = appModel.toolLocator.statuses[kind] {
                if let path = status.path {
                    lines.append("\(kind.displayName)：已找到（\(path)）")
                    if let version = status.version, !version.isEmpty {
                        lines.append("    版本：\(version)")
                    }
                } else {
                    lines.append("\(kind.displayName)：未找到")
                }
            }
        }
        lines.append("")
        lines.append("== 当前配置 ==")
        let settings = appModel.settings
        lines.append("任务：\(settings.task.title)")
        lines.append("超分后端：\(settings.backend.displayName) / 模型 \(settings.srModel) / \(settings.scale)x")
        lines.append("补帧模型：\(settings.interpModel) / \(settings.fpsMultiplier)x")
        lines.append("编码器：\(settings.encoder.displayName)")
        lines.append("性能档位：\(settings.performance.displayName) / GPU #\(settings.gpuIndex)")
        lines.append("中间帧：\(settings.intermediateFormat.displayName) / 输出目录：\(settings.outputDirectory.path)")
        lines.append("")
        lines.append("== 最近日志 ==")
        lines.append(appModel.log.plainText)
        return lines.joined(separator: "\n")
    }
}
