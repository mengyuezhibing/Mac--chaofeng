import SwiftUI

// MARK: - 运行面板（进度 + 阶段）

struct RunPanelView: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(appModel.status.label, systemImage: icon)
                    .font(.headline)
                Spacer()
                if !appModel.outputs.isEmpty {
                    Button {
                        appModel.revealOutput(appModel.outputs.last!)
                    } label: {
                        Label("在访达中显示", systemImage: "folder.badge.gearshape")
                    }
                }
                if appModel.isRunning {
                    Button(role: .destructive) {
                        appModel.cancel()
                    } label: {
                        Label("取消", systemImage: "stop.fill")
                    }
                } else {
                    Button {
                        appModel.start()
                    } label: {
                        Label("开始处理", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!appModel.canStart)
                }
            }

            ProgressView(value: appModel.status.overallFraction) {
                HStack {
                    Text(appModel.status.detail.isEmpty
                         ? "总进度 \(Int(appModel.status.overallFraction * 100))%"
                         : "\(appModel.status.detail) · 总进度 \(Int(appModel.status.overallFraction * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("当前阶段 \(Int(appModel.status.stageFraction * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = appModel.errorMessage {
                errorBox(error)
            }
        }
    }

    private var icon: String {
        switch appModel.status.stage {
        case .idle: return "circle"
        case .preparing, .probing: return "magnifyingglass"
        case .extracting: return "square.on.square"
        case .upscaling: return "wand.and.stars"
        case .interpolating: return "timelapse"
        case .encoding: return "film.stack"
        case .finished: return "checkmark.seal.fill"
        }
    }

    private func errorBox(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("任务失败", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout.weight(.semibold))
            ScrollView {
                Text(text)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 110)
            HStack {
                Button("复制错误") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Button("导出诊断信息") {
                    exportDiagnostics()
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.4)))
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MacVision-Diagnostic.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let report = DiagnosticsService.buildReport(appModel: appModel, machine: nil)
        try? report.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - 日志控制台

struct LogConsoleView: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("运行日志")
                    .font(.callout.weight(.semibold))
                Spacer()
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appModel.log.plainText, forType: .string)
                }
                .controlSize(.small)
                Button("清空") { appModel.log.clear() }
                    .controlSize(.small)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(appModel.log.lines) { line in
                            Text(line.renderedLine)
                                .font(.caption.monospaced())
                                .foregroundStyle(color(for: line.level))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(line.id)
                        }
                    }
                    .padding(6)
                }
                .frame(minHeight: 140, maxHeight: 240)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
                .onChange(of: appModel.log.lines.count) { _ in
                    if let last = appModel.log.lines.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .info: return .primary
        case .command: return .secondary
        case .warn: return .orange
        case .error: return .red
        case .success: return .green
        }
    }
}
