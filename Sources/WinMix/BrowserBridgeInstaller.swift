import Foundation

/// The per-user Chrome registration. This does not install or connect the extension itself.
enum BrowserBridgeInstaller {
    // Keep the existing host identity so installed extensions continue to work after the rename.
    static let hostName = "com.rogerleite.macvolume.chrome"
    static var defaultHostDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts", isDirectory: true)
    }

    struct Registration: Equatable {
        let extensionID: String
        let bridgeURL: URL
        var appURL: URL { bridgeURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    }

    enum InstallationError: LocalizedError {
        case invalidExtensionID, invalidAppBundle, symlinkDestination, unrelatedRegistration, registrationChanged
        case replacementRequired(Registration)

        var errorDescription: String? {
            switch self {
            case .invalidExtensionID:
                return "The extension ID must contain exactly 32 lowercase letters from a to p."
            case .invalidAppBundle:
                return "Open the bundled WinMix.app. It must include an executable ChromeBridge and a valid ChromeExtension manifest."
            case .symlinkDestination:
                return "The browser registration is a symbolic link. WinMix cannot replace it."
            case .unrelatedRegistration:
                return "The existing browser registration is not a valid WinMix registration. It has been left unchanged."
            case .registrationChanged:
                return "The browser registration changed while connecting. Review the saved connection and try again."
            case .replacementRequired:
                return "A different WinMix connection is saved. Review its app and extension ID, then select Replace this saved registration."
            }
        }
    }

    private struct Manifest: Codable, Equatable {
        let name: String
        let description: String
        let path: String
        let type: String
        let allowed_origins: [String]

        var registration: Registration? {
            guard name == hostName, type == "stdio",
                  ["WinMix Chrome tab controls", "MacVolume Chrome tab controls"].contains(description),
                  allowed_origins.count == 1 else { return nil }
            let origin = allowed_origins[0]
            let prefix = "chrome-extension://"
            guard origin.hasPrefix(prefix), origin.hasSuffix("/") else { return nil }
            let id = String(origin.dropFirst(prefix.count).dropLast())
            guard normalizedExtensionID(id) == id else { return nil }
            let bridge = URL(fileURLWithPath: path)
            guard path.hasPrefix("/"), bridge.standardizedFileURL.path == path,
                  bridge.lastPathComponent == "ChromeBridge",
                  bridge.deletingLastPathComponent().lastPathComponent == "MacOS",
                  bridge.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Contents",
                  bridge.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().pathExtension == "app"
            else { return nil }
            return Registration(extensionID: id, bridgeURL: bridge)
        }
    }

    static func normalizedExtensionID(_ value: String) -> String? {
        let id = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.count == 32, id.utf8.allSatisfy({ (97...112).contains($0) }) else { return nil }
        return id
    }

    static func existingRegistration(hostDirectory: URL = defaultHostDirectory) throws -> Registration? {
        try existingManifest(at: destination(in: hostDirectory))?.registration
    }

    @discardableResult
    static func install(extensionID: String, appURL: URL, hostDirectory: URL = defaultHostDirectory,
                        replace: Bool = false) throws -> URL {
        guard let id = normalizedExtensionID(extensionID) else { throw InstallationError.invalidExtensionID }
        let app = appURL.standardizedFileURL.resolvingSymlinksInPath()
        let bridge = app.appendingPathComponent("Contents/MacOS/ChromeBridge")
        let extensionManifest = app.appendingPathComponent("Contents/Resources/ChromeExtension/manifest.json")
        let manager = FileManager.default
        guard app.isFileURL, app.pathExtension == "app", isDirectory(app),
              isRegularFile(bridge), manager.isExecutableFile(atPath: bridge.path),
              isRegularFile(extensionManifest),
              let data = try? Data(contentsOf: extensionManifest),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              manifest["manifest_version"] as? Int == 3,
              (manifest["permissions"] as? [String])?.contains("nativeMessaging") == true
        else { throw InstallationError.invalidAppBundle }

        let desired = Manifest(name: hostName, description: "WinMix Chrome tab controls", path: bridge.path,
                               type: "stdio", allowed_origins: ["chrome-extension://\(id)/"])
        let target = destination(in: hostDirectory)
        let original = try existingManifest(at: target)
        if let existing = original {
            // A legacy description does not require replacing an otherwise identical connection.
            if existing.registration == desired.registration { return target }
            guard replace else { throw InstallationError.replacementRequired(existing.registration!) }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var output = try encoder.encode(desired)
        output.append(0x0A)
        try manager.createDirectory(at: hostDirectory, withIntermediateDirectories: true)
        // Recheck immediately before the atomic write; never follow a registration symlink.
        guard try existingManifest(at: target) == original else { throw InstallationError.registrationChanged }
        try output.write(to: target, options: .atomic)
        return target
    }

    private static func destination(in directory: URL) -> URL { directory.appendingPathComponent(hostName + ".json") }

    private static func existingManifest(at url: URL) throws -> Manifest? {
        let manager = FileManager.default
        // attributesOfItem sees dangling links too, unlike fileExists.
        let attributes: [FileAttributeKey: Any]
        do { attributes = try manager.attributesOfItem(atPath: url.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
        guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
            throw InstallationError.symlinkDestination
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["name", "description", "path", "type", "allowed_origins"]),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data), manifest.registration != nil
        else { throw InstallationError.unrelatedRegistration }
        return manifest
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
