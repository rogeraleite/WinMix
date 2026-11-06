import SwiftUI

/// Service identity comes from the hostname, independently of the selected skin.
struct BrowserTabIcon: View {
    let domain: String
    let appearance: MixerAppearance

    private var host: String { domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
    private var isMusic: Bool { host == "music.youtube.com" || host.hasSuffix(".music.youtube.com") }
    private var isYouTube: Bool {
        host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be"
    }
    private var service: String { isMusic ? "YouTube Music" : isYouTube ? "YouTube" : domain }
    private let red = Color(red: 1, green: 0, blue: 0)

    var body: some View {
        Group {
            if isMusic {
                Circle().fill(red)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.2).padding(3.5))
                    .overlay(Image(systemName: "play.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(.white).offset(x: 0.7))
                    .frame(width: 22, height: 22)
            } else if isYouTube {
                RoundedRectangle(cornerRadius: 4).fill(red)
                    .overlay(Image(systemName: "play.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.white).offset(x: 0.7))
                    .frame(width: 23, height: 16)
            } else {
                Image(systemName: "globe").font(.system(size: 17))
                    .foregroundStyle(appearance == .ceramic ? Ceramic.secondary : .white.opacity(0.65))
            }
        }
        .frame(width: 25, height: 24)
        .accessibilityLabel(service)
        .help(service)
    }
}
