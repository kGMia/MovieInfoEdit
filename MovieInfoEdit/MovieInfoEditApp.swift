import SwiftUI

@main
struct MovieInfoEditApp: App {
    @State private var appState = AppState()
    
    // 监听系统级存储
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.zhHans.rawValue
    
    var lang: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .zhHans }
    var appTheme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .system }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(appTheme.colorScheme)
        }
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar) // 隐藏系统原生标题栏
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 MovieInfoEdit") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.credits: NSAttributedString(
                                string: "一款优雅的视频元数据批处理工具。\n由 August 开发并开源。",
                                attributes: [.font: NSFont.systemFont(ofSize: 11)]
                            ),
                            NSApplication.AboutPanelOptionKey.version: "1.0.0"
                        ]
                    )
                }
            }
            
            CommandGroup(replacing: .newItem) {
                Button(tr("Import Videos", lang: lang) + "...") {
                    NotificationCenter.default.post(name: .init("TriggerImportVideos"), object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Menu(tr("Open Recent", lang: lang)) {
                    Text(tr("No Recent Files", lang: lang)).disabled(true)
                }
            }
            
            CommandMenu(tr("Process", lang: lang)) {
                Button(tr("Add to Queue", lang: lang)) {
                    NotificationCenter.default.post(name: .init("TriggerAddToQueue"), object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
                
                Button(tr("Process Queue", lang: lang)) {
                    appState.processQueue()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        
        // 恢复系统的偏好设置菜单 (Cmd + ,)
        Settings {
            SettingsView()
                .preferredColorScheme(appTheme.colorScheme)
        }
    }
}
