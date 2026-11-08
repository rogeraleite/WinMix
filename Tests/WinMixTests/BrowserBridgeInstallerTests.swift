import XCTest
@testable import WinMix

final class BrowserBridgeInstallerTests: XCTestCase {
    private var root: URL!
    private var app: URL!
    private var hosts: URL!
    private let extensionID = "abcdefghijklmnopabcdefghijklmnop"
    private let otherID = String(repeating: "b", count: 32)

    private var destination: URL { hosts.appendingPathComponent(BrowserBridgeInstaller.hostName + ".json") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("WinMixInstallerTests-" + UUID().uuidString)
        app = root.appendingPathComponent("Roger's Mac $(literal)/Win Mix's `literal`.app", isDirectory: true)
        hosts = root.appendingPathComponent("Chrome Host Registrations", isDirectory: true)
        let bridge = app.appendingPathComponent("Contents/MacOS/ChromeBridge")
        let manifest = app.appendingPathComponent("Contents/Resources/ChromeExtension/manifest.json")
        try FileManager.default.createDirectory(at: bridge.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: bridge)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bridge.path)
        try JSONSerialization.data(withJSONObject: ["manifest_version": 3, "permissions": ["nativeMessaging"]])
            .write(to: manifest)
    }

    override func tearDownWithError() throws {
        if let root { try FileManager.default.removeItem(at: root) }
    }

    func testWritesOneOriginWithLiteralPathsAndNoTemporaryFiles() throws {
        XCTAssertNil(try BrowserBridgeInstaller.existingRegistration(hostDirectory: hosts))
        let target = try BrowserBridgeInstaller.install(extensionID: " \(extensionID)\n", appURL: app, hostDirectory: hosts)
        XCTAssertEqual(target, destination)
        let manifest = try readManifest()
        XCTAssertEqual(manifest["name"] as? String, "com.rogerleite.macvolume.chrome")
        XCTAssertEqual(manifest["type"] as? String, "stdio")
        XCTAssertEqual(manifest["path"] as? String, app.appendingPathComponent("Contents/MacOS/ChromeBridge").path)
        XCTAssertEqual(manifest["allowed_origins"] as? [String], ["chrome-extension://\(extensionID)/"])
        let saved = try XCTUnwrap(BrowserBridgeInstaller.existingRegistration(hostDirectory: hosts))
        XCTAssertEqual(saved.extensionID, extensionID)
        XCTAssertEqual(saved.appURL, app)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: hosts.path), [destination.lastPathComponent])
    }

    func testRejectsInvalidIDsWithoutCreatingRegistrationDirectory() throws {
        for id in ["", String(repeating: "a", count: 31), String(repeating: "a", count: 33),
                   String(repeating: "q", count: 32), String(repeating: "A", count: 32),
                   String(repeating: "é", count: 32), extensionID + "/"] {
            XCTAssertThrowsError(try BrowserBridgeInstaller.install(extensionID: id, appURL: app, hostDirectory: hosts))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: hosts.path))
    }

    func testRejectsMissingOrInvalidAppComponents() throws {
        XCTAssertThrowsError(try BrowserBridgeInstaller.install(extensionID: extensionID, appURL: root, hostDirectory: hosts))
        let bridge = app.appendingPathComponent("Contents/MacOS/ChromeBridge")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: bridge.path)
        XCTAssertThrowsError(try BrowserBridgeInstaller.install(extensionID: extensionID, appURL: app, hostDirectory: hosts))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bridge.path)
        let manifest = app.appendingPathComponent("Contents/Resources/ChromeExtension/manifest.json")
        try Data("not json".utf8).write(to: manifest)
        XCTAssertThrowsError(try BrowserBridgeInstaller.install(extensionID: extensionID, appURL: app, hostDirectory: hosts))
        try FileManager.default.removeItem(at: manifest)
        XCTAssertThrowsError(try BrowserBridgeInstaller.install(extensionID: extensionID, appURL: app, hostDirectory: hosts))
        XCTAssertFalse(FileManager.default.fileExists(atPath: hosts.path))
    }

    func testIdenticalAndLegacyRegistrationsAreIdempotent() throws {
        try install()
        var manifest = try readManifest()
        manifest["description"] = "MacVolume Chrome tab controls"
        try writeManifest(manifest)
        let original = try Data(contentsOf: destination)
        let oldDate = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: destination.path)
        try install()
        XCTAssertEqual(try Data(contentsOf: destination), original)
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        XCTAssertEqual(attributes[.modificationDate] as? Date, oldDate)
    }

    func testDifferentRegistrationRequiresExplicitReplacement() throws {
        try install()
        let original = try Data(contentsOf: destination)
        XCTAssertThrowsError(try BrowserBridgeInstaller.install(extensionID: otherID, appURL: app, hostDirectory: hosts)) { error in
            guard case BrowserBridgeInstaller.InstallationError.replacementRequired(let saved) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(saved.extensionID, self.extensionID)
            XCTAssertEqual(saved.appURL, self.app)
        }
        XCTAssertEqual(try Data(contentsOf: destination), original)
        try BrowserBridgeInstaller.install(extensionID: otherID, appURL: app, hostDirectory: hosts, replace: true)
        XCTAssertEqual(try BrowserBridgeInstaller.existingRegistration(hostDirectory: hosts)?.extensionID, otherID)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: hosts.path), [destination.lastPathComponent])
    }

    func testMovedAppRegistrationCanBeReviewedAndUpdated() throws {
        try install()
        let moved = root.appendingPathComponent("Moved WinMix.app", isDirectory: true)
        try FileManager.default.moveItem(at: app, to: moved)
        XCTAssertEqual(try BrowserBridgeInstaller.existingRegistration(hostDirectory: hosts)?.appURL, app)
        XCTAssertThrowsError(try BrowserBridgeInstaller.install(extensionID: extensionID, appURL: moved, hostDirectory: hosts))
        try BrowserBridgeInstaller.install(extensionID: extensionID, appURL: moved, hostDirectory: hosts, replace: true)
        XCTAssertEqual(try BrowserBridgeInstaller.existingRegistration(hostDirectory: hosts)?.appURL, moved)
    }

    func testUnrelatedOrMalformedFilesAreNeverReplacedOrPrefilled() throws {
        try install()
        let valid = try readManifest()
        var unrelated = valid
        unrelated["name"] = "another.app"
        var multipleOrigins = valid
        multipleOrigins["allowed_origins"] = ["chrome-extension://\(extensionID)/", "chrome-extension://\(otherID)/"]
        var invalidOrigin = valid
        invalidOrigin["allowed_origins"] = ["https://example.com/"]
        var invalidPath = valid
        invalidPath["path"] = "/bin/sh"
        var extraKey = valid
        extraKey["unrelated"] = true
        for manifest in [unrelated, multipleOrigins, invalidOrigin, invalidPath, extraKey] {
            try writeManifest(manifest)
            try assertRegistrationRefusedAndPreserved()
        }
        try Data("not json".utf8).write(to: destination)
        try assertRegistrationRefusedAndPreserved()
    }

    func testSymlinkAndDanglingSymlinkDestinationsAreRefused() throws {
        try FileManager.default.createDirectory(at: hosts, withIntermediateDirectories: true)
        let linked = root.appendingPathComponent("unrelated.json")
        let original = Data("leave unchanged".utf8)
        try original.write(to: linked)
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: linked)
        XCTAssertThrowsError(try BrowserBridgeInstaller.existingRegistration(hostDirectory: hosts))
        XCTAssertThrowsError(try BrowserBridgeInstaller.install(extensionID: extensionID, appURL: app, hostDirectory: hosts, replace: true))
        XCTAssertEqual(try Data(contentsOf: linked), original)
        try FileManager.default.removeItem(at: linked)
        XCTAssertThrowsError(try BrowserBridgeInstaller.existingRegistration(hostDirectory: hosts))
        XCTAssertThrowsError(try BrowserBridgeInstaller.install(extensionID: extensionID, appURL: app, hostDirectory: hosts, replace: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: linked.path))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path), linked.path)
    }

    func testValidationFailureLeavesExistingManifestUntouched() throws {
        try install()
        let original = try Data(contentsOf: destination)
        try FileManager.default.removeItem(at: app.appendingPathComponent("Contents/MacOS/ChromeBridge"))
        XCTAssertThrowsError(try BrowserBridgeInstaller.install(extensionID: otherID, appURL: app, hostDirectory: hosts, replace: true))
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: hosts.path), [destination.lastPathComponent])
    }

    private func install() throws {
        try BrowserBridgeInstaller.install(extensionID: extensionID, appURL: app, hostDirectory: hosts)
    }

    private func readManifest() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: destination)) as? [String: Any])
    }

    private func writeManifest(_ manifest: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: manifest).write(to: destination)
    }

    private func assertRegistrationRefusedAndPreserved(file: StaticString = #filePath, line: UInt = #line) throws {
        let original = try Data(contentsOf: destination)
        XCTAssertThrowsError(try BrowserBridgeInstaller.existingRegistration(hostDirectory: hosts), file: file, line: line)
        XCTAssertThrowsError(try BrowserBridgeInstaller.install(extensionID: otherID, appURL: app, hostDirectory: hosts, replace: true), file: file, line: line)
        XCTAssertEqual(try Data(contentsOf: destination), original, file: file, line: line)
    }
}
