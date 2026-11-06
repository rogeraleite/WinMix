import SwiftUI
import ChromeSupport

struct ChromeTabsView: View {
    @ObservedObject var model: ChromeTabModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Lamp(isOn: model.connected, color: Skin.green)
                Text("CHROME TABS").font(Skin.label(11)).foregroundStyle(Skin.amber)
                Spacer()
                Button("SETUP") { if let url = ChromeTabModel.guideURL { NSWorkspace.shared.open(url) } }
                    .font(Skin.label(9))
                    .buttonStyle(SkinButtonStyle())
                    .help("Open Chrome extension installation instructions")
            }
            Text(model.status)
                .font(Skin.label(10)).foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            if !model.tabs.isEmpty {
                Text("Chrome's app volume is the master for all tabs.")
                    .font(Skin.label(9)).foregroundStyle(Skin.amber.opacity(0.8))
                ForEach(model.tabs) { tab in
                    ChromeTabRow(tab: tab, connected: model.connected, pending: model.pending[tab.id] != nil,
                                 setVolume: { model.setVolume($0, for: tab) }, toggleMute: { model.toggleMute(tab) })
                }
            }
            if let error = model.error {
                Text(error).font(Skin.label(10)).foregroundStyle(Skin.amber).textSelection(.enabled)
            }
        }
        .padding(8)
        .background(Skin.chrome)
        .bevel()
    }
}

private struct ChromeTabRow: View {
    let tab: ChromeTab
    let connected: Bool
    let pending: Bool
    let setVolume: (Double) -> Void
    let toggleMute: () -> Void
    private var enabled: Bool { connected && tab.controlled && !pending }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Lamp(isOn: connected && tab.audible)
                Text(tab.title).font(Skin.label(11)).lineLimit(1)
                    .help(tab.title).foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 0)
                Text("#\(tab.id)").font(Skin.label(9)).foregroundStyle(.white.opacity(0.5))
            }
            Text("\(tab.domain) · \(stateText)")
                .font(Skin.label(9)).foregroundStyle(tab.controlled && tab.issue == nil ? Skin.green : Skin.amber)
                .fixedSize(horizontal: false, vertical: true)
            if tab.controlled || tab.canMute == true {
                HStack(spacing: 8) {
                    Button(action: toggleMute) {
                        Image(systemName: tab.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .foregroundStyle(tab.muted ? Skin.red : .white)
                    }
                    .buttonStyle(SkinButtonStyle())
                    .accessibilityLabel("\(tab.muted ? "Unmute" : "Mute") \(tab.title), tab \(tab.id)")
                    .disabled(!connected || pending)
                    if tab.controlled {
                        LEDSlider(value: Binding(get: { tab.volume }, set: setVolume), maximum: 1,
                                  isMuted: tab.muted, label: "\(tab.title), tab \(tab.id) volume")
                            .disabled(!enabled)
                        DotText(text: "\(Int((tab.volume * 100).rounded()))%", color: tab.muted ? Skin.bevelHighlight : Skin.green)
                            .frame(width: 50, alignment: .trailing)
                    } else {
                        Text("Volume unavailable · mute available").font(Skin.label(9)).foregroundStyle(Skin.amber)
                        Spacer(minLength: 0)
                    }
                }
                .opacity(connected && !pending ? 1 : 0.5)
            }
        }
        .padding(6)
        .background(Skin.display)
        .bevel(raised: false)
    }

    private var stateText: String {
        if !connected { return "DISCONNECTED · last confirmed state" }
        if let issue = tab.issue { return issue }
        if !tab.controlled { return "Reload MacVolume Tabs once for automatic YouTube controls" }
        if pending { return "APPLYING…" }
        if tab.muted { return "MUTED" }
        return tab.audible ? "PLAYING" : "PAUSED"
    }
}
