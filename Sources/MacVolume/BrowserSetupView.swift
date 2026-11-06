import AppKit
import SwiftUI

enum BrowserSetup {
    static func normalizedExtensionID(_ value: String) -> String? {
        let id = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.count == 32, id.utf8.allSatisfy({ (97...112).contains($0) }) else { return nil }
        return id
    }

    static func connectionCommand(extensionID: String, scriptURL: URL, appURL: URL, replace: Bool = false) -> String? {
        guard let id = normalizedExtensionID(extensionID) else { return nil }
        return "python3 \(shellQuote(scriptURL.path)) \(shellQuote(id)) --app \(shellQuote(appURL.path))"
            + (replace ? " --replace" : "")
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct BrowserSetupView: View {
    var chrome: ChromeTabModel? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var extensionID = ""
    @State private var replaceRegistration = false
    @State private var copied = false
    @State private var copiedFolder = false
    @State private var openError: String?

    private var chromeURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") }
    private var extensionURL: URL? {
        ChromeTabModel.extensionURL.flatMap { FileManager.default.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) ? $0 : nil }
    }
    private var scriptURL: URL? {
        Bundle.main.resourceURL.flatMap { resources in
            let url = resources.appendingPathComponent("scripts/install-chrome-bridge.py")
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }
    private var command: String? {
        guard let scriptURL, Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return BrowserSetup.connectionCommand(extensionID: extensionID, scriptURL: scriptURL,
                                              appURL: Bundle.main.bundleURL, replace: replaceRegistration)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Control browser tabs").font(.system(size: 22, weight: .semibold))
                    Text("Install MacVolume Tabs for Google Chrome.")
                        .font(.system(size: 12)).foregroundStyle(Ceramic.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let chrome { BrowserConnectionStatus(model: chrome) }

                    step(1, "Open Chrome extensions") {
                        Text("Open chrome://extensions and turn on Developer mode in the top-right corner.")
                        Button("Open Chrome Extensions", action: openChromeExtensions)
                            .disabled(chromeURL == nil)
                        if chromeURL == nil { Text("Install Google Chrome to use this integration.").foregroundStyle(Ceramic.secondary) }
                    }
                    step(2, "Load MacVolume Tabs") {
                        Text("Choose Load unpacked, then select the ChromeExtension folder included with MacVolume. Keep the app in its permanent location before connecting it.")
                        HStack {
                            Button("Show Extension Folder") {
                                if let extensionURL { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: extensionURL.path) }
                            }
                            Button(copiedFolder ? "Path Copied" : "Copy Folder Path") {
                                guard let extensionURL else { return }
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(extensionURL.path, forType: .string)
                                copiedFolder = true
                            }
                        }
                        .disabled(extensionURL == nil)
                        Text("In Chrome's folder picker, press ⇧⌘G and paste the copied folder path.")
                            .foregroundStyle(Ceramic.secondary)
                        if extensionURL == nil {
                            Text("Open the bundled MacVolume.app to access the extension and installer.").foregroundStyle(Ceramic.secondary)
                        }
                    }
                    step(3, "Connect the extension to MacVolume") {
                        Text("Copy the 32-letter ID shown on the MacVolume Tabs card in Chrome. Paste it below, copy the command, and run it once in Terminal. Python 3 is required.")
                        TextField("Extension ID from chrome://extensions", text: $extensionID)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Chrome extension ID")
                            .onChange(of: extensionID) { _, _ in copied = false }
                        if !extensionID.isEmpty && BrowserSetup.normalizedExtensionID(extensionID) == nil {
                            Text("The ID must contain exactly 32 lowercase letters from a to p.").foregroundStyle(Ceramic.blue)
                        }
                        Toggle("Update the connection after moving MacVolume", isOn: $replaceRegistration)
                            .font(.system(size: 11))
                            .onChange(of: replaceRegistration) { _, _ in copied = false }
                        if let command {
                            Text(command).font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Ceramic.inset, in: RoundedRectangle(cornerRadius: 6))
                        }
                        HStack {
                            Button(copied ? "Copied" : "Copy Connection Command") {
                                guard let command else { return }
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(command, forType: .string)
                                copied = true
                            }
                            .disabled(command == nil)
                            Button("Open Terminal") {
                                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                                }
                            }
                        }
                    }
                    step(4, "Allow sites and start playing") {
                        Text("In the extension's Details, allow access to the sites you want to control. Keep MacVolume open, then click Reconnect in MacVolume Tabs. Play audio or video in a tab; its controls appear automatically. Reload pages that were already open if they do not appear.")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Already installed?").font(.system(size: 13, weight: .semibold))
                        Text("Reload MacVolume Tabs in chrome://extensions using its original folder and ID, approve site access, then reload older pages if needed. Repeat the connection step only if the app path or extension ID changed.")
                        Text("The Chrome app slider is the master for all tabs. Compatible audio/video players get volume, mute and play/pause. Other audio sources may offer mute only.")
                            .foregroundStyle(Ceramic.secondary)
                    }
                    if let openError { Text(openError).foregroundStyle(Ceramic.blue) }
                }
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .padding(24)
            }
        }
        .frame(width: 560, height: 650)
        .background(Ceramic.surface)
        .foregroundStyle(Ceramic.ink)
        .tint(Ceramic.blue)
        .preferredColorScheme(.light)
    }

    private func step<Content: View>(_ number: Int, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Ceramic.blue)
                .frame(width: 25, height: 25).background(Ceramic.inset, in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 14, weight: .semibold))
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func openChromeExtensions() {
        guard let chromeURL, let url = URL(string: "chrome://extensions/") else { return }
        NSWorkspace.shared.open([url], withApplicationAt: chromeURL, configuration: .init()) { _, error in
            if let error { DispatchQueue.main.async { openError = error.localizedDescription } }
        }
    }
}

private struct BrowserConnectionStatus: View {
    @ObservedObject var model: ChromeTabModel

    var body: some View {
        Label(model.connected ? "Chrome is connected" : "Chrome is not connected yet",
              systemImage: model.connected ? "checkmark.circle.fill" : "link")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(model.connected ? Ceramic.blue : Ceramic.secondary)
    }
}
