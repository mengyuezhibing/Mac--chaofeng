import AppKit
import SwiftUI

// MARK: - 偏好设置（Cmd+,）

struct PreferencesView: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        Form {
            Section("界面外观") {
                Picker("主题色", selection: $appModel.accentColorName) {
                    ForEach(ThemeColor.choices, id: \.name) { choice in
                        HStack {
                            Circle().fill(choice.color).frame(width: 12, height: 12)
                            Text(choice.label)
                        }
                        .tag(choice.name)
                    }
                }
                Picker("外观", selection: $appModel.appearanceRaw) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
            }

            Section("工具路径（留空自动搜索 Homebrew / 应用内 / 用户目录）") {
                ForEach(ToolKind.allCases) { kind in
                    HStack {
                        Text(kind.displayName)
                            .frame(width: 170, alignment: .leading)
                        TextField("自动检测", text: Binding(
                            get: { appModel.toolOverrides[kind.rawValue] ?? "" },
                            set: { appModel.toolOverrides[kind.rawValue] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        Button("浏览…") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = true
                            panel.canChooseDirectories = false
                            panel.directoryURL = ToolLocator.applicationSupportBin
                            if panel.runModal() == .OK, let url = panel.url {
                                appModel.toolOverrides[kind.rawValue] = url.path
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section("临时目录") {
                Text(AppModel.defaultTempRoot.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("处理视频时中间帧会写入该目录，任务结束后自动清理（可在工作台选择保留）")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560, height: 480)
        .onDisappear {
            Task { await appModel.refreshEnvironment() }
        }
    }
}
