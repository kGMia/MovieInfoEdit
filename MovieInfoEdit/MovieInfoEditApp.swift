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
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L("About MovieInfoEdit")) {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.credits: NSAttributedString(
                                string: L("About Description"),
                                attributes: [.font: NSFont.systemFont(ofSize: 11)]
                            ),
                            NSApplication.AboutPanelOptionKey.version: "1.0.0"
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
            }
        }

        Settings {
            SettingsView()
                .preferredColorScheme(appTheme.colorScheme)
        }
    }
}
