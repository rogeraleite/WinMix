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
                                 togglePlayback: { model.setPlayback(tab.playing == true ? "pause" : "play", for: tab) },
                                 setTransport: { model.setTransport($0, for: tab) })
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
    let setTransport: (String) -> Void

    private var enabled: Bool { connected && tab.controlled }
    private var canTogglePlayback: Bool { tab.playing == true ? tab.canPause == true : tab.canPlay == true }
    private var isCeramic: Bool { appearance == .ceramic }
    private var accent: Color { isCeramic ? Ceramic.blue : Skin.green }
    private var secondary: Color { isCeramic ? Ceramic.secondary : Skin.bevelHighlight }
    private var hasTrackControls: Bool { tab.canPrevious == true || tab.canNext == true || tab.canShuffle == true }

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
                BrowserTabIcon(domain: tab.domain, appearance: appearance)
                Text(tab.title)
                    .font(isCeramic ? .system(size: 11, weight: .medium) : Skin.label(11))
                    .lineLimit(1).help(tab.title)
                    .foregroundStyle(isCeramic ? Ceramic.ink : .white.opacity(0.9))
                Spacer(minLength: 0)
                if !isCeramic {
                    Text("#\(tab.id)").font(Skin.label(9)).foregroundStyle(.white.opacity(0.5))
                }
            }
            Text("\(tab.domain) · \(stateText)\(shuffleStatus)")
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
            if let issue = tab.transportIssue {
                Text(issue).font(.system(size: 9))
                    .foregroundStyle(isCeramic ? Ceramic.secondary : Skin.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if tab.domain == "music.youtube.com" && tab.canNext == nil {
                Text("Reload WinMix Tabs and this page to enable track controls.")
                    .font(.system(size: 9))
                    .foregroundStyle(isCeramic ? Ceramic.secondary : Skin.amber)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            if hasTrackControls {
                trackButton("previous", symbol: "backward.end.fill", label: "Previous track", supported: tab.canPrevious == true)
            }
            Button(action: togglePlayback) {
                Image(systemName: tab.playing == true ? "pause.fill" : "play.fill")
                    .foregroundStyle(canTogglePlayback ? accent : secondary)
            }
            .buttonStyle(TabControlStyle(appearance: appearance))
            .accessibilityLabel("\(tab.playing == true ? "Pause" : "Play") \(tab.title), tab \(tab.id)")
            .accessibilityValue(tab.playing == true ? "Playing" : tab.playing == false ? "Paused" : "Unknown")
            .help(controlHelp(state: "Playback: \(tab.playing == true ? "Playing" : tab.playing == false ? "Paused" : "Unknown")",
                              action: tab.playing == true ? "Click to pause." : "Click to resume.", supported: canTogglePlayback,
                              unavailable: tab.playbackIssue ?? "Playback unavailable. Start the player on the website once; older pages may need a reload."))
            .disabled(!connected || pending || !canTogglePlayback)

            if hasTrackControls {
                trackButton("next", symbol: "forward.end.fill", label: "Next track", supported: tab.canNext == true)
                if tab.canShuffle == true, let shuffled = tab.shuffleEnabled {
                    trackButton(shuffled ? "shuffle-off" : "shuffle-on", symbol: "shuffle",
                                label: shuffled ? "Turn shuffle off" : "Turn shuffle on", supported: true, selected: shuffled)
                        .accessibilityValue(shuffled ? "On" : "Off")
                }
            }

            Button(action: toggleMute) {
                Image(systemName: tab.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(isCeramic ? tab.muted ? Ceramic.blue : Ceramic.secondary : tab.muted ? Skin.red : .white)
            }
            .buttonStyle(TabControlStyle(appearance: appearance, selected: tab.muted))
            .accessibilityLabel("\(tab.muted ? "Unmute" : "Mute") \(tab.title), tab \(tab.id)")
            .accessibilityValue(tab.muted ? "Muted" : "Not muted")
            .help(controlHelp(state: "Mute: \(tab.muted ? "On" : "Off")", action: tab.muted ? "Click to unmute." : "Click to mute.",
                              supported: tab.canMute == true || tab.controlled, unavailable: "Mute is unavailable for this tab."))
            .disabled(!connected || pending || !(tab.canMute == true || tab.controlled))

            if tab.controlled {
                if isCeramic {
                    CeramicVolumeSlider(value: Binding(get: { displayedVolume }, set: setVolume), maximum: 1,
                                        isMuted: tab.muted, label: "\(tab.title), tab \(tab.id) volume")
                        .disabled(!enabled)
                        .help(volumeHelp)
                    Text("\(Int((displayedVolume * 100).rounded()))%")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Ceramic.ink).frame(width: 34, alignment: .trailing)
                } else {
                    LEDSlider(value: Binding(get: { displayedVolume }, set: setVolume), maximum: 1,
                              isMuted: tab.muted, label: "\(tab.title), tab \(tab.id) volume")
                        .disabled(!enabled)
                        .help(volumeHelp)
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

    private func trackButton(_ action: String, symbol: String, label: String, supported: Bool, selected: Bool = false) -> some View {
        Button { setTransport(action) } label: {
            Image(systemName: symbol)
                .foregroundStyle(selected ? accent : supported ? (isCeramic ? Ceramic.ink : .white) : secondary)
                .opacity(supported ? 1 : 0.35)
        }
        .buttonStyle(TabControlStyle(appearance: appearance, selected: selected))
        .overlay(alignment: .bottomTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10)).foregroundStyle(accent)
                    .background(.white, in: Circle()).offset(x: 2, y: 2)
                    .accessibilityHidden(true).allowsHitTesting(false)
            }
        }
        .accessibilityLabel("\(label): \(tab.title), tab \(tab.id)")
        .help(controlHelp(
            state: action.hasPrefix("shuffle-") ? "Shuffle: \(selected ? "On" : "Off")" : "\(label): \(supported ? "Available" : "Unavailable")",
            action: action == "previous" ? "Click for the previous track; the player may restart the current track."
                : action == "next" ? "Click to skip to the next track."
                : selected ? "Click to turn off." : "Click to turn on.",
            supported: supported, unavailable: "The player does not currently offer this control."))
        .disabled(!connected || pending || !supported)
    }

    private var shuffleStatus: String {
        guard tab.canShuffle == true, let shuffled = tab.shuffleEnabled else { return "" }
        return shuffled ? " · Shuffle on" : " · Shuffle off"
    }

    private func controlHelp(state: String, action: String, supported: Bool, unavailable: String) -> String {
        if !connected { return "\(state) (last confirmed). Chrome is disconnected; reconnect to use this control." }
        if pending { return "\(state) (last confirmed). Applying a change; waiting for the player to confirm." }
        return "\(state). \(supported ? action : unavailable)"
    }

    private var volumeHelp: String {
        if !connected { return "Volume: \(Int((tab.volume * 100).rounded()))% (last confirmed). Chrome is disconnected." }
        if pending { return "Volume: \(Int((displayedVolume * 100).rounded()))%. A change is awaiting confirmation; you can keep adjusting the slider." }
        return MixerControlHelp.volume(displayedVolume, maximum: 1, muted: tab.muted)
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
    var selected = false

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if appearance == .ceramic {
            CeramicButtonStyle(active: selected).makeBody(configuration: configuration)
        } else {
            SkinButtonStyle().makeBody(configuration: configuration)
                .overlay {
                    if selected { Rectangle().strokeBorder(Skin.green.opacity(0.85), lineWidth: 1.5).allowsHitTesting(false) }
                }
        }
    }
}
