import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var loginItem: LoginItemModel

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(get: { loginItem.isEnabled }, set: loginItem.setEnabled))

            if loginItem.status == .requiresApproval {
                Text("macOS needs your approval before MacVolume can open at login.")
                    .foregroundStyle(.secondary)
                Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let error = loginItem.error {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            }

            Divider()
            Text("Chrome tab controls").font(.headline)
            Text("Install MacVolume Tabs and allow access to YouTube and YouTube Music. Playing tabs appear automatically.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Show Chrome Extension Folder") {
                if let url = ChromeTabModel.extensionURL { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path) }
            }
            Button("Open Installation Instructions") {
                if let url = ChromeTabModel.guideURL { NSWorkspace.shared.open(url) }
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear(perform: loginItem.refresh)
    }
}
