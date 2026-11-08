import SwiftUI

@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--probe") {
            exit(Probe.run(arguments: CommandLine.arguments))
        }
        if CommandLine.arguments.contains("--preview-ui") {
            MixerPreviewApp.main()
            return
        }
        WinMixApp.main()
    }
}

struct WinMixApp: App {
    // Owned by the app, not the window, so taps keep running when the window is closed.
    @StateObject private var permission = PermissionModel()
    @StateObject private var mixer = MixerModel()
    @StateObject private var loginItem = LoginItemModel()
    @StateObject private var chrome = ChromeTabModel()
    @StateObject private var navigation = AppNavigation()

    var body: some Scene {
        Window("WinMix", id: "mixer") {
            Group {
                // "Not determined" goes straight to the mixer: macOS asks (or grants) on the first tap.
                if permission.status == .denied {
                    PermissionView(permission: permission)
                } else {
                    MixerView(model: mixer, chrome: chrome, navigation: navigation)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                permission.refresh()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 510, height: 420)
        .windowResizability(.contentMinSize)

        MenuBarExtra("WinMix", systemImage: "slider.horizontal.3") {
            MenuBarSceneContent(model: mixer, permission: permission, navigation: navigation)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(loginItem: loginItem, chrome: chrome)
        }
    }
}
