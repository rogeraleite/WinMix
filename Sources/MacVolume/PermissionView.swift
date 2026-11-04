import SwiftUI

struct PermissionView: View {
    @ObservedObject var permission: PermissionModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "speaker.wave.2.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Allow MacVolume to control app audio")
                .font(.title2.weight(.semibold))

            Text("To change an app's volume, MacVolume reads that app's audio and plays it back at the level you choose. macOS calls this System Audio Recording. Nothing is recorded or saved.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Access is currently off. In System Settings, open **Privacy & Security → Screen & System Audio Recording** and turn on MacVolume under **System Audio Recording Only**.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
                .keyboardShortcut(.defaultAction)
                Button("Check Again", action: permission.refresh)
            }
        }
        .padding(32)
        .frame(width: 420)
    }
}
