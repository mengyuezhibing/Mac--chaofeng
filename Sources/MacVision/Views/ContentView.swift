import SwiftUI

// MARK: - 主窗口

enum SidebarItem: String, CaseIterable, Identifiable {
    case workspace = "工作台"
    case environment = "环境检测"
    case about = "关于"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .workspace: return "slider.horizontal.3"
        case .environment: return "stethoscope"
        case .about: return "info.circle"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var selection: SidebarItem = .workspace

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.rawValue, systemImage: item.symbol)
                        .tag(item)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(180)
        } detail: {
            Group {
                switch selection {
                case .workspace: WorkspaceView()
                case .environment: EnvironmentView()
                case .about: AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        }
        .navigationTitle("Mac图片与视频超分")
        .alert("依赖未就绪", isPresented: $appModel.showEnvironmentAlert) {
            Button("前往环境检测") { selection = .environment }
            Button("取消", role: .cancel) {}
        } message: {
            Text("尚未检测到 FFmpeg/FFprobe。请先在「环境检测」页安装依赖，或在偏好设置中手动指定路径。")
        }
    }
}

// MARK: - 工作台

struct WorkspaceView: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card(title: "01 选择素材", systemImage: "square.and.arrow.down.on.square") {
                    SourceDropView()
                }
                Card(title: "02 选择任务", systemImage: "list.bullet.rectangle") {
                    TaskPickerView()
                }
                Card(title: "03 确认设置", systemImage: "slider.horizontal.3") {
                    SettingsPanelView()
                }
                Card(title: "04 跟踪结果", systemImage: "chart.line.uptrend.xyaxis") {
                    RunPanelView()
                    Divider()
                    LogConsoleView()
                }
            }
            .padding(.bottom, 30)
        }
        .scrollIndicators(.never)
    }
}

// MARK: - 关于

struct AboutView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "snowflake")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
            Text("Mac图片与视频超分")
                .font(.title2.weight(.semibold))
            Text("面向零基础用户的本地 AI 图片与视频增强工具\n支持图片超分、视频超分、视频补帧、超分并补帧")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Mac 版基于原 Windows 版的公开功能与技术栈实现：\nncnn-vulkan（Metal/MoltenVK）+ FFmpeg + VideoToolbox 硬件编码")
                .multilineTextAlignment(.center)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("本应用只提供本地处理流程，不提供素材、不内置模型下载，请确保素材拥有合法处理权限。")
                .multilineTextAlignment(.center)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
