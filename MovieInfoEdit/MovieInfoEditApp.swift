import SwiftUI

@main
struct MovieInfoEditApp: App {
    @State private var appState = AppState()

    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue

    var appTheme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .system }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(appTheme.colorScheme)
        }
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L("About MovieInfoEdit")) {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.credits: NSAttributedString(
                                string: L("About Description"),
                                attributes: [.font: NSFont.systemFont(ofSize: 11)]
                            ),
                            NSApplication.AboutPanelOptionKey.version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
                        ]
                    )
                }
            }

            CommandGroup(replacing: .newItem) {
                Button(L("Import Videos") + "...") {
                    NotificationCenter.default.post(name: .init("TriggerImportVideos"), object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Menu(L("Open Recent")) {
                    Text(L("No Recent Files")).disabled(true)
                }
            }

            CommandMenu(L("Process")) {
                Button(L("Add to Queue")) {
                    NotificationCenter.default.post(name: .init("TriggerAddToQueue"), object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Button(L("Process Queue")) {
                    appState.processQueue()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!appState.canProcessQueue)
                Button(L("Write History")) { appState.showingHistory = true }
                Button(L("Check Library")) { appState.checkLibrary() }
                Button(L("Save Session")) { appState.saveSessionNow() }
            }
        }

        Settings {
            SettingsView()
                .preferredColorScheme(appTheme.colorScheme)
        }
    }
}
