import XCTest
@testable import MacVolume

final class BrowserSetupTests: XCTestCase {
    func testRejectsIDsThatCannotBeChromeExtensionIDs() {
        let script = URL(fileURLWithPath: "/installer.py"), app = URL(fileURLWithPath: "/MacVolume.app")
        for id in ["", String(repeating: "a", count: 31), String(repeating: "a", count: 33),
                   String(repeating: "q", count: 32), String(repeating: "A", count: 32),
                   "abcdefghijklmnop; touch /tmp/test", String(repeating: "é", count: 32)] {
            XCTAssertNil(BrowserSetup.connectionCommand(extensionID: id, scriptURL: script, appURL: app), id)
        }
        XCTAssertNotNil(BrowserSetup.connectionCommand(extensionID: "  abcdefghijklmnopabcdefghijklmnop\n", scriptURL: script, appURL: app))
    }

    func testCopiedCommandPreservesPathsAsSingleShellArguments() throws {
        // Execute only printf to inspect shell parsing, never the real installer.
        let script = URL(fileURLWithPath: "/Users/Roger's Mac/$(echo unsafe)/install.py")
        let app = URL(fileURLWithPath: "/Applications/Mac Volume's `echo unsafe`.app")
        let id = "abcdefghijklmnopabcdefghijklmnop"
        let command = try XCTUnwrap(BrowserSetup.connectionCommand(extensionID: id, scriptURL: script, appURL: app, replace: true))
        let shell = Process(), pipe = Pipe()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "printf '%s\\n' " + String(command.dropFirst("python3 ".count))]
        shell.standardOutput = pipe
        try shell.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        shell.waitUntilExit()
        XCTAssertEqual(shell.terminationStatus, 0)
        XCTAssertEqual(String(decoding: output, as: UTF8.self).split(separator: "\n").map(String.init),
                       [script.path, id, "--app", app.path, "--replace"])
    }
}
