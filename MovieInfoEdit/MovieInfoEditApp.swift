import SwiftUI

@main
struct MovieInfoEditApp: App {
    @StateObject private var appState = AppState()
    
    // 直接监听系统存储，保证最高优先级的重绘
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.zhHans.rawValue
    
    var lang: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .zhHans }
    var appTheme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .system }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(appTheme.colorScheme)
        }
        .commands {
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
        
        Settings {
            SettingsView()
                .environmentObject(appState)
                .preferredColorScheme(appTheme.colorScheme)
        }
    }
}
