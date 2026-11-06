import SwiftUI
import ChromeSupport

struct ChromeTabsView: View {
    @ObservedObject var model: ChromeTabModel
    var appearance: MixerAppearance = .retro
    @State private var showingSetup = false

    private var isCeramic: Bool { appearance == .ceramic }

    var body: some View {
        Group {
            if isCeramic {
                content.padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1).fill(Ceramic.blue.opacity(0.3)).frame(width: 2)
                    }
            } else {
                content.padding(8).background(Skin.chrome).bevel()
            }
        }
        .sheet(isPresented: $showingSetup) { BrowserSetupView(chrome: model) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if isCeramic {
                    Circle().fill(model.connected ? Ceramic.blue : Ceramic.secondary.opacity(0.5))
                        .frame(width: 5, height: 5).accessibilityHidden(true)
                } else {
                    Lamp(isOn: model.connected, color: Skin.green)
                }
                Text(isCeramic ? "Browser tabs" : "CHROME TABS")
                    .font(isCeramic ? .system(size: 11, weight: .semibold) : Skin.label(11))
                    .foregroundStyle(isCeramic ? Ceramic.ink : Skin.amber)
                Spacer()
                Button(isCeramic ? "Setup" : "SETUP") { showingSetup = true }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(isCeramic ? Ceramic.blue : Skin.amber)
                    .help("Install or update the Chrome extension")
            }
            Text(model.status)
                .font(isCeramic ? .system(size: 10) : Skin.label(10))
                .foregroundStyle(isCeramic ? Ceramic.secondary : .white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            if !model.tabs.isEmpty {
                Text("Chrome's app volume is the master for all tabs.")
                    .font(isCeramic ? .system(size: 10) : Skin.label(9))
                    .foregroundStyle(isCeramic ? Ceramic.secondary : Skin.amber.opacity(0.8))
                ForEach(model.tabs) { tab in
                    ChromeTabRow(tab: tab, appearance: appearance, connected: model.connected,
                                 pending: model.pending[tab.id] != nil,
                                 displayedVolume: model.requestedVolumes[tab.id] ?? tab.volume,
                                 setVolume: { model.setVolume($0, for: tab) },
                                 toggleMute: { model.toggleMute(tab) },
                                 togglePlayback: { model.setPlayback(tab.playing == true ? "pause" : "play", for: tab) })
                }
            }
            if let error = model.error {
                Text(error).font(.system(size: 10))
                    .foregroundStyle(isCeramic ? Ceramic.blue : Skin.amber)
                    .textSelection(.enabled)
            }
        }
    }
}

/// Shared capability checks and callbacks; only presentation varies by appearance.
private struct ChromeTabRow: View {
    let tab: ChromeTab
    let appearance: MixerAppearance
    let connected: Bool
    let pending: Bool
    let displayedVolume: Double
    let setVolume: (Double) -> Void
    let toggleMute: () -> Void
    let togglePlayback: () -> Void

    private var enabled: Bool { connected && tab.controlled }
    private var canTogglePlayback: Bool { tab.playing == true ? tab.canPause == true : tab.canPlay == true }
    private var isCeramic: Bool { appearance == .ceramic }
    private var accent: Color { isCeramic ? Ceramic.blue : Skin.green }
    private var secondary: Color { isCeramic ? Ceramic.secondary : Skin.bevelHighlight }

    var body: some View {
        Group {
            if isCeramic { content.padding(.vertical, 8) }
            else { content.padding(6).background(Skin.display).bevel(raised: false) }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if !isCeramic { Lamp(isOn: connected && tab.audible) }
                Text(tab.title)
                    .font(isCeramic ? .system(size: 11, weight: .medium) : Skin.label(11))
                    .lineLimit(1).help(tab.title)
                    .foregroundStyle(isCeramic ? Ceramic.ink : .white.opacity(0.9))
                Spacer(minLength: 0)
                if !isCeramic {
                    Text("#\(tab.id)").font(Skin.label(9)).foregroundStyle(.white.opacity(0.5))
                }
            }
            Text("\(tab.domain) · \(stateText)")
                .font(isCeramic ? .system(size: 9) : Skin.label(9))
                .foregroundStyle(isCeramic ? Ceramic.secondary : tab.controlled && tab.issue == nil ? Skin.green : Skin.amber)
                .fixedSize(horizontal: false, vertical: true)
            if tab.controlled || tab.canMute == true || tab.canPlay == true || tab.canPause == true {
                controls.opacity(connected ? 1 : 0.5)
            }
            if let issue = tab.playbackIssue {
                Text(issue).font(.system(size: 9))
                    .foregroundStyle(isCeramic ? Ceramic.secondary : Skin.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button(action: togglePlayback) {
                Image(systemName: tab.playing == true ? "pause.fill" : "play.fill")
                    .foregroundStyle(canTogglePlayback ? accent : secondary)
            }
            .buttonStyle(TabControlStyle(appearance: appearance))
            .accessibilityLabel("\(tab.playing == true ? "Pause" : "Play") \(tab.title), tab \(tab.id)")
            .help(tab.playbackIssue ?? (canTogglePlayback
                ? (tab.playing == true ? "Pause this tab" : "Resume this tab")
                : "Playback unavailable; start the player on the website once. Older pages may need a reload."))
            .disabled(!connected || pending || !canTogglePlayback)

            Button(action: toggleMute) {
                Image(systemName: tab.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(isCeramic ? tab.muted ? Ceramic.blue : Ceramic.secondary : tab.muted ? Skin.red : .white)
            }
            .buttonStyle(TabControlStyle(appearance: appearance))
            .accessibilityLabel("\(tab.muted ? "Unmute" : "Mute") \(tab.title), tab \(tab.id)")
            .disabled(!connected || pending || !(tab.canMute == true || tab.controlled))

            if tab.controlled {
                if isCeramic {
                    CeramicVolumeSlider(value: Binding(get: { displayedVolume }, set: setVolume), maximum: 1,
                                        isMuted: tab.muted, label: "\(tab.title), tab \(tab.id) volume")
                        .disabled(!enabled)
                    Text("\(Int((displayedVolume * 100).rounded()))%")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Ceramic.ink).frame(width: 34, alignment: .trailing)
                } else {
                    LEDSlider(value: Binding(get: { displayedVolume }, set: setVolume), maximum: 1,
                              isMuted: tab.muted, label: "\(tab.title), tab \(tab.id) volume")
                        .disabled(!enabled)
                    DotText(text: "\(Int((displayedVolume * 100).rounded()))%", color: tab.muted ? Skin.bevelHighlight : Skin.green)
                        .frame(width: 50, alignment: .trailing)
                }
            } else {
                Text("Volume unavailable · mute available").font(.system(size: 9))
                    .foregroundStyle(isCeramic ? Ceramic.secondary : Skin.amber)
                Spacer(minLength: 0)
            }
        }
    }

    private var stateText: String {
        if !connected { return "Disconnected · last confirmed state" }
        if let issue = tab.issue { return issue }
        if !tab.controlled { return "Volume unavailable for this audio source" }
        if pending { return isCeramic ? "Applying…" : "APPLYING…" }
        if tab.muted { return tab.playing == true ? "Playing · muted" : "Muted" }
        if let playing = tab.playing { return playing ? "Playing" : "Paused" }
        return tab.audible ? "Audio active" : "Playback state unavailable"
    }
}

private struct TabControlStyle: ButtonStyle {
    let appearance: MixerAppearance

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if appearance == .ceramic {
            CeramicButtonStyle().makeBody(configuration: configuration)
        } else {
            SkinButtonStyle().makeBody(configuration: configuration)
        }
    }
}
