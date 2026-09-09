import SwiftUI

@main
struct SnowLeopardVisionApp: App {
    @StateObject private var appModel = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup("Mac图片与视频超分") {
            ContentView()
                .environmentObject(appModel)
                .frame(minWidth: 1120, minHeight: 720)
                .preferredColorScheme(AppearanceMode(rawValue: appModel.appearanceRaw)?.colorScheme)
                .tint(appModel.accentColor)
                .task { await appModel.refreshEnvironment() }
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(after: .newItem) {
                Button("选择素材…") { appModel.pickFiles() }
                    .keyboardShortcut("o")
                Divider()
                Button(appModel.isRunning ? "取消任务" : "开始处理") {
                    if appModel.isRunning { appModel.cancel() } else { appModel.start() }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!appModel.canStart && !appModel.isRunning)
            }
        }

        Settings {
            PreferencesView()
                .environmentObject(appModel)
                .frame(width: 520)
        }
    }
}
