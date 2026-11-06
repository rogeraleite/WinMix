import SwiftUI

@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--probe") {
            exit(Probe.run(arguments: CommandLine.arguments))
        }
        MacVolumeApp.main()
    }
}

struct MacVolumeApp: App {
    // Owned by the app, not the window, so taps keep running when the window is closed.
    @StateObject private var permission = PermissionModel()
    @StateObject private var mixer = MixerModel()
    @StateObject private var loginItem = LoginItemModel()
    @StateObject private var chrome = ChromeTabModel()

    var body: some Scene {
        WindowGroup("MacVolume") {
            Group {
                // "Not determined" goes straight to the mixer: macOS asks (or grants) on the first tap.
                if permission.status == .denied {
                    PermissionView(permission: permission)
                } else {
                    MixerView(model: mixer, chrome: chrome)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                permission.refresh()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 480, height: 340)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(loginItem: loginItem)
        }
    }
}
