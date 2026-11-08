import AppKit
import SwiftUI

enum BrowserSetup {
    static func normalizedExtensionID(_ value: String) -> String? {
        BrowserBridgeInstaller.normalizedExtensionID(value)
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
    /// Explicit paths allow isolated setup validation without changing the user's registration.
    var appURL = Bundle.main.bundleURL
    var hostDirectory = BrowserBridgeInstaller.defaultHostDirectory
    @Environment(\.dismiss) private var dismiss
    @State private var extensionID = ""
    @State private var replaceRegistration = false
    @State private var copiedFolder = false
    @State private var openError: String?
    @State private var registration: BrowserBridgeInstaller.Registration?
    @State private var registrationError: String?
    @State private var installError: String?
    @State private var registrationSaved = false

    private var chromeURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") }
    private var extensionURL: URL? {
        let url = appURL.appendingPathComponent("Contents/Resources/ChromeExtension", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("manifest.json").path) ? url : nil
    }
    private var needsReplacement: Bool {
        guard let registration else { return false }
        let app = appURL.standardizedFileURL.resolvingSymlinksInPath()
        return registration.appURL != app || registration.extensionID != BrowserSetup.normalizedExtensionID(extensionID)
    }
    private var canConnect: Bool {
        BrowserSetup.normalizedExtensionID(extensionID) != nil && extensionURL != nil
            && appURL.pathExtension == "app" && registrationError == nil
            && (!needsReplacement || replaceRegistration)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Control browser tabs").font(.system(size: 22, weight: .semibold))
                    Text("Install WinMix Tabs for Google Chrome.")
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
                    step(2, "Load WinMix Tabs") {
                        Text("Choose Load unpacked, then select the ChromeExtension folder included with WinMix. Keep the app in its permanent location before connecting it.")
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
                            Text("Open the bundled WinMix.app to access the extension and installer.").foregroundStyle(Ceramic.secondary)
                        }
                    }
                    step(3, "Connect the extension to WinMix") {
                        Text("Copy the 32-letter ID shown on the WinMix Tabs card in Chrome, paste it below, then click Connect browser.")
                        TextField("Extension ID from chrome://extensions", text: $extensionID)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Chrome extension ID")
                            .onChange(of: extensionID) { _, _ in
                                replaceRegistration = false
                                registrationSaved = false
                                installError = nil
                            }
                        if !extensionID.isEmpty && BrowserSetup.normalizedExtensionID(extensionID) == nil {
                            Text("The ID must contain exactly 32 lowercase letters from a to p.").foregroundStyle(Ceramic.blue)
                        }
                        if let registration, needsReplacement {
                            Text("Saved app: \(registration.appURL.path)\nSaved extension ID: \(registration.extensionID)")
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Ceramic.inset, in: RoundedRectangle(cornerRadius: 6))
                            Toggle("Replace this saved registration", isOn: $replaceRegistration)
                                .font(.system(size: 11))
                                .help("Update only this WinMix connection after changing the app location or extension ID.")
                        }
                        Button("Connect browser", action: connectBrowser)
                            .disabled(!canConnect)
                            .help("Save this extension's connection to WinMix for your macOS user.")
                        if registrationSaved || (registration != nil && !needsReplacement) {
                            Label("Browser registration saved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Ceramic.blue)
                            Text("In WinMix Tabs, click Reconnect. The live connection status above confirms when Chrome connects.")
                                .foregroundStyle(Ceramic.secondary)
                        }
                        if let registrationError { Text(registrationError).foregroundStyle(Ceramic.blue) }
                        if let installError { Text(installError).foregroundStyle(Ceramic.blue) }
                    }
                    step(4, "Allow sites and start playing") {
                        Text("In the extension's Details, allow access to the sites you want to control. Keep WinMix open, then click Reconnect in WinMix Tabs. Play audio or video in a tab; its controls appear automatically. Reload pages that were already open if they do not appear.")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Already installed?").font(.system(size: 13, weight: .semibold))
                        Text("Reload WinMix Tabs in chrome://extensions using its original folder and ID, approve site access, then reload older pages if needed. Repeat the connection step only if the app path or extension ID changed.")
                        Text("The Chrome app slider is the master for all tabs. Compatible audio/video players get volume, mute and play/pause. Other audio sources may offer mute only.")
                            .foregroundStyle(Ceramic.secondary)
                        Text("YouTube Music also offers previous, next and shuffle when its player supports them. After updating WinMix Tabs, reload the music page once to enable new track controls.")
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
        .onAppear(perform: loadRegistration)
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

    private func loadRegistration() {
        do {
            registration = try BrowserBridgeInstaller.existingRegistration(hostDirectory: hostDirectory)
            registrationError = nil
            if extensionID.isEmpty, let registration {
                extensionID = registration.extensionID
            }
        } catch {
            registration = nil
            registrationSaved = false
            registrationError = error.localizedDescription
        }
    }

    private func connectBrowser() {
        do {
            try BrowserBridgeInstaller.install(extensionID: extensionID, appURL: appURL, hostDirectory: hostDirectory,
                                               replace: replaceRegistration)
            registration = try BrowserBridgeInstaller.existingRegistration(hostDirectory: hostDirectory)
            registrationSaved = true
            replaceRegistration = false
            installError = nil
        } catch {
            installError = error.localizedDescription
            loadRegistration()
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
