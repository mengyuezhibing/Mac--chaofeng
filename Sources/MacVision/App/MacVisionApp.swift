import SwiftUI

@main
struct MacVisionApp: App {
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
            // 显式汉化左上角「应用」菜单，避免随系统语言回落到英文
            CommandGroup(replacing: .appInfo) {
                Button("关于 Mac图片与视频超分") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "Mac图片与视频超分",
                        .applicationVersion: "1.0.0",
                        .version: "1.0.0",
                        .credits: NSAttributedString(
                            string: "本地 AI 图片与视频增强工具\n支持图片超分、视频超分、视频补帧、超分并补帧",
                            attributes: [.font: NSFont.systemFont(ofSize: 11)]
                        )
                    ])
                }
            }
            // 注意：不要再用 .appSettings 手动添加「设置…」，
            // SwiftUI 的 Settings scene 已自动生成并本地化为「设置…」，重复添加会出现两项
            CommandGroup(replacing: .appTermination) {
                Button("退出 Mac图片与视频超分") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            CommandGroup(replacing: .systemServices) { }  // 移除「服务」子菜单
            CommandGroup(replacing: .help) { }            // 移除「帮助」菜单
            CommandGroup(replacing: .newItem) {
                Button("选择素材…") { appModel.pickFiles() }
                    .keyboardShortcut("o")
                Divider()
                Button(appModel.isRunning ? "取消任务" : "开始处理") {
                    if appModel.isRunning { appModel.cancel() } else { appModel.start() }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!appModel.canStart && !appModel.isRunning)
            }
            CommandGroup(replacing: .windowArrangement) {
                Button("最小化") { NSApplication.shared.keyWindow?.miniaturize(nil) }
                    .keyboardShortcut("m", modifiers: .command)
                Button("缩放") { NSApplication.shared.keyWindow?.zoom(nil) }
            }
        }

        Settings {
            PreferencesView()
                .environmentObject(appModel)
                .frame(width: 520)
        }
    }

}
