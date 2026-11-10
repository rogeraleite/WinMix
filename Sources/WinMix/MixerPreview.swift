import Foundation
import SwiftUI
import ChromeSupport

/// Explicit UI diagnostic fixture: no process observer, socket, defaults or real audio.
@MainActor
enum MixerPreview {
    static var appearance: MixerAppearance {
        let arguments = CommandLine.arguments
        return arguments.firstIndex(of: "--preview-appearance")
            .flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            .flatMap(MixerAppearance.init(rawValue:)) ?? .stickerCase
    }

    static func chrome() -> ChromeTabModel {
        guard CommandLine.arguments.contains("--preview-tabs") else {
            return ChromeTabModel(previewTabs: [], connected: false)
        }
        let data = Data(#"{"version":1,"type":"state","session":"preview","tabs":[{"id":41,"title":"Lo-fi radio","domain":"youtube.com","audible":true,"controlled":true,"volume":0.45,"muted":false,"canMute":true,"playing":true,"canPlay":true,"canPause":true,"canNext":true},{"id":42,"title":"Evening mix","domain":"music.youtube.com","audible":false,"controlled":true,"volume":0.8,"muted":false,"canMute":true,"playing":false,"canPlay":true,"canPause":true,"canPrevious":true,"canNext":true,"canShuffle":true,"shuffleEnabled":false}]}"#.utf8)
        return ChromeTabModel(previewTabs: (try? BridgeMessage.decode(data).tabs) ?? [], connected: true)
    }

    static let devices = [AudioOutputDevice(uid: "preview-speakers", name: "MacBook Pro Speakers"),
                          AudioOutputDevice(uid: "preview-headphones", name: "USB Headphones")]

    static func model(many: Bool = false) -> MixerModel {
        let keys = many ? (1...12).map { "preview.long.application.name.for.truncation.\($0)" }
            : ["com.google.Chrome", "com.microsoft.teams2", "com.apple.Music", "net.whatsapp.WhatsApp"]
        let rows = keys.enumerated().map { index, key in
            AppGroup(key: key, identity: ProcessIdentity(pid: -1, bundleID: key),
                     processes: [AudioProcess(id: UInt32(90000 + index), pid: -90000 - Int32(index),
                                              bundleID: key, isPlaying: index != 1)])
        }
        return MixerModel(previewRows: rows, settings: [
            "com.google.Chrome": VolumeSetting(volume: 0.3),
            "com.microsoft.teams2": VolumeSetting(volume: 0.8, isMuted: true),
            "com.apple.Music": VolumeSetting(volume: 1),
            "net.whatsapp.WhatsApp": VolumeSetting(volume: 1.6)
        ], boostEnabled: true, outputName: devices[0].name, outputDevices: devices)
    }
}

/// Diagnostic window uses the exact panel and models when automation cannot target status items.
struct MixerPreviewCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Preview") {
            Button("Open Mini Mixer Preview") { openWindow(id: "menu-preview") }
        }
    }
}

/// Separate entry point keeps diagnostic scenes and fake services outside the live app lifecycle.
struct MixerPreviewApp: App {
    @StateObject private var model = MixerPreview.model(many: CommandLine.arguments.contains("--preview-many"))
    @StateObject private var permission = PermissionModel(readStatus: {
        CommandLine.arguments.contains("--preview-denied") ? .denied : .authorized
    })
    @StateObject private var chrome = MixerPreview.chrome()
    @StateObject private var navigation = AppNavigation()
    @StateObject private var loginItem = LoginItemModel()
    private let hostDirectory: URL

    init() {
        let arguments = CommandLine.arguments
        hostDirectory = arguments.firstIndex(of: "--preview-host-directory")
            .flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("WinMixUIPreview-" + UUID().uuidString)
    }

    var body: some Scene {
        Window("WinMix Preview", id: "mixer") {
            Group {
                if permission.status == .denied {
                    PermissionView(permission: permission)
                } else {
                    MixerView(model: model, chrome: chrome, appearanceOverride: MixerPreview.appearance,
                              navigation: navigation, setupHostDirectory: hostDirectory)
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 600, height: 620)
        .windowResizability(.contentMinSize)
        .commands { MixerPreviewCommands() }

        Window("Mini Mixer Preview", id: "menu-preview") {
            MenuBarSceneContent(model: model, permission: permission, navigation: navigation)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("WinMix", systemImage: "slider.horizontal.3") {
            MenuBarSceneContent(model: model, permission: permission, navigation: navigation)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(loginItem: loginItem, chrome: chrome, setupHostDirectory: hostDirectory,
                         allowsLoginChanges: false)
        }
    }
}
