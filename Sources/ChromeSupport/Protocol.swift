import Foundation

public struct ChromeTab: Codable, Identifiable, Equatable {
    public var id: Int
    public var title: String
    public var domain: String
    public var audible: Bool
    public var controlled: Bool
    public var volume: Double
    public var muted: Bool
    public var issue: String?
    public var canMute: Bool?
    public var controlMode: String?
    public var playing: Bool?
    public var canPlay: Bool?
    public var canPause: Bool?
    public var playbackIssue: String?
}

public struct BridgeMessage: Codable {
    public var version = 1
    public var type: String
    public var session: String?
    public var requestID: String?
    public var tabID: Int?
    public var volume: Double?
    public var muted: Bool?
    public var tabs: [ChromeTab]?
    public var error: String?
    public var mode: String?
    public var action: String?

    public init(type: String, session: String? = nil, requestID: String? = nil,
                tabID: Int? = nil, volume: Double? = nil, muted: Bool? = nil, error: String? = nil, action: String? = nil) {
        self.type = type; self.session = session; self.requestID = requestID
        self.tabID = tabID; self.volume = volume; self.muted = muted; self.error = error
        self.action = action
    }

    public func validate() throws {
        guard version == 1, ["ready", "state", "set", "playback", "shutdown", "error"].contains(type),
              (session?.count ?? 0) <= 80, (requestID?.count ?? 0) <= 80,
              (error?.count ?? 0) <= 1024, mode == nil || mode == "automatic-youtube",
              action == nil || (type == "playback" && ["play", "pause"].contains(action ?? "")) else { throw BridgeError.invalidMessage }
        if let volume { guard volume.isFinite && (0...1).contains(volume) else { throw BridgeError.invalidMessage } }
        if let tabID { guard tabID >= 0 else { throw BridgeError.invalidMessage } }
        if type == "set" {
            guard session?.isEmpty == false, requestID?.isEmpty == false,
                  tabID != nil, volume != nil, muted != nil else { throw BridgeError.invalidMessage }
        }
        if type == "playback" {
            guard session?.isEmpty == false, requestID?.isEmpty == false,
                  tabID != nil, action != nil, volume == nil, muted == nil else { throw BridgeError.invalidMessage }
        }
        if type == "state" {
            guard session?.isEmpty == false, let tabs, tabs.count <= 500,
                  Set(tabs.map(\.id)).count == tabs.count else { throw BridgeError.invalidMessage }
            for tab in tabs {
                guard tab.id >= 0, tab.title.count <= 512, tab.domain.count <= 256,
                      (tab.issue?.count ?? 0) <= 512,
                      (tab.playbackIssue?.count ?? 0) <= 512,
                      tab.controlMode == nil || tab.controlMode == "page",
                      tab.volume.isFinite, (0...1).contains(tab.volume) else { throw BridgeError.invalidMessage }
            }
        }
    }

    public static func decode(_ data: Data) throws -> BridgeMessage {
        let message = try JSONDecoder().decode(Self.self, from: data)
        try message.validate()
        return message
    }

    public func encoded() throws -> Data {
        try validate()
        return try JSONEncoder().encode(self)
    }
}

public enum BridgeError: Error, LocalizedError {
    case invalidMessage, invalidFrame, system(String)
    public var errorDescription: String? {
        switch self {
        case .invalidMessage: return "Invalid Chrome bridge message or protocol version."
        case .invalidFrame: return "Invalid or incomplete Chrome bridge frame."
        case .system(let text): return text
        }
    }
}
