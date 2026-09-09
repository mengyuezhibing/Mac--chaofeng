import AppKit
import SwiftUI

// MARK: - 环境检测页

struct EnvironmentView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var machineInfo: MachineInfo?
    @State private var isChecking = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card(title: "设备信息", systemImage: "desktopcomputer") {
                    if let machineInfo {
                        Text(machineInfo.summary)
                            .font(.callout.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    } else {
                        Text("正在读取设备信息…")
                            .foregroundStyle(.secondary)
                    }
                }

                Card(title: "依赖工具", systemImage: "shippingbox") {
                    VStack(spacing: 8) {
                        ForEach(ToolKind.allCases) { kind in
                            toolRow(kind)
                        }
                    }
                    HStack {
                        Button {
                            isChecking = true
                            Task {
                                await appModel.refreshEnvironment()
                                machineInfo = await DeviceService.probeMachineInfo()
                                isChecking = false
                            }
                        } label: {
                            if isChecking {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("重新检测", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(isChecking)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(
                                "brew install ffmpeg\nbash Scripts/install_deps.sh",
                                forType: .string)
                        } label: {
                            Label("复制安装命令", systemImage: "doc.on.doc")
                        }
                    }
                    .padding(.top, 4)

                    Text("安装方式：\n1. FFmpeg：运行 brew install ffmpeg（需先安装 Homebrew）\n2. ncnn 超分/补帧工具：运行仓库内的 Scripts/install_deps.sh，脚本会自动下载 macOS 版并放入 ~/Library/Application Support/MacVision/bin\n3. 也可以手动下载工具后，在偏好设置中指定路径")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task {
            machineInfo = await DeviceService.probeMachineInfo()
        }
    }

    private func toolRow(_ kind: ToolKind) -> some View {
        let status = appModel.toolLocator.statuses[kind]
        return HStack(spacing: 10) {
            Image(systemName: status?.found == true ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(status?.found == true ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(kind.displayName).font(.callout.weight(.medium))
                    if kind.isRequired {
                        Text("必需").font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.2)))
                    }
                }
                if let path = status?.path {
                    Text(path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    if let version = status?.version {
                        Text(version)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                } else {
                    Text(kind.purpose)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let repo = kind.repository {
                Button("下载页") {
                    if let url = URL(string: "https://github.com/\(repo)/releases") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
