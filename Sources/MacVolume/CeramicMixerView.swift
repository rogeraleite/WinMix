import SwiftUI

struct CeramicMixerView: View {
    @ObservedObject var model: MixerModel
    var chrome: ChromeTabModel?
    @Binding var appearance: MixerAppearance
    let showSetup: () -> Void

    private var hasChromeMaster: Bool { model.rows.contains { $0.key == "com.google.Chrome" } }

    var body: some View {
        VStack(spacing: 0) {
            header
            outputStrip
            Divider().overlay(Ceramic.edge)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        VStack(spacing: 0) {
                            appRow(row)
                            if row.key == "com.google.Chrome", let chrome {
                                ChromeTabsView(model: chrome, appearance: .ceramic)
                                    .padding(.leading, 30)
                                    .padding(.trailing, 12)
                                    .padding(.bottom, 12)
                            }
                        }
                        .background(row.key == "com.google.Chrome" && chrome != nil ? Ceramic.inset.opacity(0.7) : .clear)
                        if row.id != model.rows.last?.id {
                            Divider().overlay(Ceramic.edge.opacity(0.7)).padding(.horizontal, 18)
                        }
                    }
                    if !hasChromeMaster, let chrome {
                        ChromeTabsView(model: chrome, appearance: .ceramic)
                            .padding(16)
                    }
                    if model.rows.isEmpty { emptyState }
                }
                .padding(.vertical, 4)
            }
            if let error = model.error { errorBanner(error) }
        }
        .frame(minWidth: 460, minHeight: 280)
        .background(LinearGradient(colors: [.white, Ceramic.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
        .foregroundStyle(Ceramic.ink)
        .tint(Ceramic.blue)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("MacVolume").font(.system(size: 17, weight: .semibold))
            Spacer(minLength: 8)
            MixerHeaderControls(appearance: $appearance, showSetup: showSetup)
        }
        .padding(.leading, 78)
        .padding(.trailing, 14)
        .frame(height: 44)
        .background(.white.opacity(0.45))
    }

    private var outputStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "headphones").foregroundStyle(Ceramic.secondary)
            Text(model.outputName.isEmpty ? "System output" : model.outputName)
                .lineLimit(1).truncationMode(.middle)
                .help(model.outputName)
            Spacer(minLength: 12)
            Toggle("Boost", isOn: $model.boostEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .fixedSize()
                .help(model.boostEnabled ? "App volume up to 200%" : "Allow app volume up to 200%")
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .padding(.top, 6)
    }

    private func appRow(_ row: AppGroup) -> some View {
        let setting = model.setting(for: row)
        return HStack(spacing: 10) {
            Image(nsImage: row.identity.icon).resizable().frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.identity.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).help(row.identity.name)
                Text(setting.isMuted ? "Muted" : row.isPlaying ? "Playing" : "Paused")
                    .font(.system(size: 10))
                    .foregroundStyle(Ceramic.secondary)
            }
            .frame(width: 105, alignment: .leading)

            Button { model.toggleMute(row) } label: {
                Image(systemName: setting.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(CeramicButtonStyle(active: setting.isMuted))
            .help(setting.isMuted ? "Unmute \(row.identity.name)" : "Mute \(row.identity.name)")
            .accessibilityLabel(setting.isMuted ? "Unmute \(row.identity.name)" : "Mute \(row.identity.name)")

            CeramicVolumeSlider(
                value: Binding(get: { min(setting.volume, model.maximumVolume) }, set: { model.setVolume($0, for: row) }),
                maximum: model.maximumVolume, isMuted: setting.isMuted, label: "\(row.identity.name) volume")

            Text("\(Int((setting.volume * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(setting.volume > 1 && !setting.isMuted ? Ceramic.blue : Ceramic.ink)
                .frame(width: 42, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "speaker.wave.2").font(.system(size: 28)).foregroundStyle(Ceramic.blue)
            Text("Ready when you press play").font(.system(size: 14, weight: .semibold))
            Text("Apps appear here when they play audio.")
                .font(.system(size: 12)).foregroundStyle(Ceramic.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(Ceramic.blue)
            Text(error).font(.system(size: 11)).textSelection(.enabled)
            Spacer(minLength: 4)
            Button { model.error = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("Dismiss error")
        }
        .padding(14).background(Ceramic.inset)
    }
}
