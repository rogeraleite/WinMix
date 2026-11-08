import AppKit
import SwiftUI

struct MenuBarSceneContent: View {
    @ObservedObject var model: MixerModel
    @ObservedObject var permission: PermissionModel
    @ObservedObject var navigation: AppNavigation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarMixerView(model: model, permissionStatus: permission.status,
                         openMixer: showMixer, openChromeSetup: {
                             navigation.requestBrowserSetup()
                             showMixer()
                         })
            .onAppear(perform: permission.refresh)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                permission.refresh()
            }
    }

    private func showMixer() {
        openWindow(id: "mixer")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
