import SwiftUI

struct MixerView: View {
    @ObservedObject var model: MixerModel
    var chrome: ChromeTabModel? = nil
    /// Rendering previews must not change the user's saved appearance.
    var appearanceOverride: MixerAppearance? = nil
    @ObservedObject var navigation = AppNavigation()
    var setupHostDirectory = BrowserBridgeInstaller.defaultHostDirectory
    @AppStorage("mixerAppearance") private var savedAppearance = MixerAppearance.ceramic
    @State private var showingSetup = false

    private var appearance: MixerAppearance { appearanceOverride ?? savedAppearance }
    private var selection: Binding<MixerAppearance> {
        Binding(get: { appearance }, set: { if appearanceOverride == nil { savedAppearance = $0 } })
    }

    var body: some View {
        Group {
            switch appearance {
            case .ceramic:
                CeramicMixerView(model: model, chrome: chrome, appearance: selection, showSetup: { showingSetup = true })
            case .retro:
                RetroMixerView(model: model, chrome: chrome, appearance: selection, showSetup: { showingSetup = true })
            }
        }
        .sheet(isPresented: $showingSetup) { BrowserSetupView(chrome: chrome, hostDirectory: setupHostDirectory) }
        .onAppear(perform: consumeSetupRequest)
        .onChange(of: navigation.browserSetupRequested) { _, requested in
            if requested { consumeSetupRequest() }
        }
    }

    private func consumeSetupRequest() {
        if navigation.consumeBrowserSetupRequest() { showingSetup = true }
    }
}

private struct RetroMixerView: View {
    @ObservedObject var model: MixerModel
    var chrome: ChromeTabModel?
    @Binding var appearance: MixerAppearance
    let showSetup: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            titleStrip
            displayPanel
            rowsPanel
            if let error = model.error { errorBanner(error) }
        }
        .frame(minWidth: 430, minHeight: 250)
        .background(Skin.chrome)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    /// Sits under the hidden title bar, so the window can be dragged by it.
    private var titleStrip: some View {
        HStack(spacing: 10) {
            Grooves()
            LogoMark()
            DotText(text: "WinMix", color: Skin.amber, dot: 1.5, gap: 0.5)
            Grooves()
            MixerHeaderControls(appearance: $appearance, showSetup: showSetup)
        }
        .padding(.leading, 76)
        .padding(.trailing, 10)
        .frame(height: 36)
        .background(Skin.chromeLight)
        .bevel()
    }

    private var displayPanel: some View {
        HStack(spacing: 8) {
            Marquee(text: displayText)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(Skin.display)
                .bevel(raised: false)

            Button { model.boostEnabled.toggle() } label: {
                HStack(spacing: 5) {
                    Lamp(isOn: model.boostEnabled, color: Skin.red)
                    Text("BOOST").font(Skin.label(10)).foregroundStyle(model.boostEnabled ? Skin.red : .white.opacity(0.75))
                }
            }
            .buttonStyle(SkinButtonStyle())
            .help(MixerControlHelp.boost(model.boostEnabled))
            .accessibilityLabel("Boost")
            .accessibilityValue(model.boostEnabled ? "On" : "Off")
        }
        .padding(8)
    }

    private var displayText: String {
        let count = model.rows.count
        let apps = count == 0 ? "No apps playing" : count == 1 ? "1 app" : "\(count) apps"
        return model.outputName.isEmpty ? apps : "\(apps) *** Out: \(model.outputName)"
    }

    @ViewBuilder
    private var rowsPanel: some View {
        Group {
            if model.rows.isEmpty && chrome == nil {
                VStack(spacing: 10) {
                    DotText(text: "No signal", color: Skin.amber, dot: 2.5, gap: 0.5)
                    Text("Play something and it will show up here.")
                        .font(Skin.label(11))
                        .foregroundStyle(Skin.green.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(model.rows) { row in
                            AppRowView(
                                row: row,
                                setting: model.setting(for: row),
                                maximumVolume: model.maximumVolume,
                                setVolume: { model.setVolume($0, for: row) },
                                toggleMute: { model.toggleMute(row) },
                                outputMenu: AppOutputMenu(model: model, row: row, appearance: .retro)
                            )
                        }
                        if let chrome { ChromeTabsView(model: chrome) }
                    }
                    .padding(4)
                }
            }
        }
        .background(Skin.bevelShadow.opacity(0.6))
        .bevel(raised: false)
        .padding([.horizontal, .bottom], 8)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Lamp(isOn: true, color: Skin.amber)
            Text(error)
                .font(Skin.label(11))
                .foregroundStyle(Skin.amber)
                .textSelection(.enabled)
            Spacer()
            Button { model.error = nil } label: {
                Text("DISMISS").font(Skin.label(10)).foregroundStyle(.white.opacity(0.75))
            }
            .buttonStyle(SkinButtonStyle())
        }
        .padding(8)
        .background(Skin.display)
        .bevel(raised: false)
        .padding([.horizontal, .bottom], 8)
    }
}

struct AppRowView: View {
    let row: AppGroup
    let setting: VolumeSetting
    let maximumVolume: Double
    let setVolume: (Double) -> Void
    let toggleMute: () -> Void
    let outputMenu: AppOutputMenu

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 8) {
            Lamp(isOn: row.isPlaying)

            Image(nsImage: row.identity.icon)
                .resizable()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.identity.name)
                    .font(Skin.label(12))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(row.isPlaying ? "PLAYING" : "PAUSED")
                    .font(Skin.label(9))
                    .foregroundStyle(row.isPlaying ? Skin.green : .white.opacity(0.45))
            }
            .frame(width: 112, alignment: .leading)

            Button(action: toggleMute) {
                Image(systemName: speakerSymbol)
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 16)
                    .foregroundStyle(setting.isMuted ? Skin.red : .white.opacity(0.85))
            }
            .buttonStyle(SkinButtonStyle())
            .help(MixerControlHelp.mute(setting.isMuted))
            .accessibilityLabel(setting.isMuted ? "Unmute \(row.identity.name)" : "Mute \(row.identity.name)")
            .accessibilityValue(setting.isMuted ? "Muted" : "Not muted")

            LEDSlider(
                value: Binding(get: { min(setting.volume, maximumVolume) }, set: setVolume),
                maximum: maximumVolume,
                isMuted: setting.isMuted,
                label: "\(row.identity.name) volume"
            )
            .help(MixerControlHelp.volume(setting.volume, maximum: maximumVolume, muted: setting.isMuted))

            DotText(text: "\(Int((setting.volume * 100).rounded()))%", color: percentColor)
                .frame(width: 50, alignment: .trailing)
        }
        outputMenu.padding(.leading, 42)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Skin.chrome)
        .bevel()
    }

    private var percentColor: Color {
        if setting.isMuted { return Skin.bevelHighlight }
        return setting.volume > 1 ? Skin.red : Skin.green
    }

    private var speakerSymbol: String {
        if setting.isMuted { return "speaker.slash.fill" }
        switch setting.volume {
        case ..<0.01: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}
