import Foundation
import Darwin
import ChromeSupport

// Only Chrome launches this executable. Its manifest restricts the exact allowed origin.
let origin = CommandLine.arguments.dropFirst().first ?? ""
guard origin.range(of: "^chrome-extension://[a-p]{32}/?$", options: .regularExpression) != nil else {
    fputs("ChromeBridge requires a Chrome extension origin.\n", stderr)
    exit(1)
}
signal(SIGPIPE, SIG_IGN)

do {
    let fd = try LocalSocket.connect()
    // A port holds the worker alive. EOF in either direction terminates both relay loops.
    DispatchQueue.global().async {
        do {
            while let data = try BridgeFrame.read(fd) {
                _ = try BridgeMessage.decode(data)
                try BridgeFrame.write(data, to: STDOUT_FILENO)
            }
            exit(0)
        } catch { exit(1) }
    }
    while let data = try BridgeFrame.read(STDIN_FILENO) {
        let message = try BridgeMessage.decode(data)
        guard ["state", "error"].contains(message.type) else { throw BridgeError.invalidMessage }
        try BridgeFrame.write(data, to: fd)
    }
    close(fd)
} catch {
    if let data = try? BridgeMessage(type: "error", error: error.localizedDescription).encoded() {
        try? BridgeFrame.write(data, to: STDOUT_FILENO)
    }
    exit(1)
}
