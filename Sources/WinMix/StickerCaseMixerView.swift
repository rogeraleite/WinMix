import SwiftUI

struct StickerCaseMixerView: View {
    @ObservedObject var model: MixerModel
    var chrome: ChromeTabModel?
    @Binding var appearance: MixerAppearance
    let showSetup: () -> Void

    private var hasChromeMaster: Bool { model.rows.contains { $0.key == "com.google.Chrome" } }

    var body: some View {
        VStack(spacing: 0) {
            header
            outputStrip
            rule
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        if row.key == "com.google.Chrome", let chrome {
                            browserGroup(row, chrome: chrome)
                                .padding(.vertical, 7)
                        } else {
                            appRow(row)
                            if row.id != model.rows.last?.id { rule.padding(.horizontal, 6) }
                        }
                    }
                    if !hasChromeMaster, let chrome {
                        ChromeTabsView(model: chrome, appearance: .stickerCase)
                            .padding(14)
                            .background(StickerPaper(tint: StickerCase.mint))
                            .clipShape(StickerOutline())
                            .overlay(StickerOutline().stroke(StickerCase.ink, lineWidth: 1.5))
                            .padding(.vertical, 7)
                    }
                    if model.rows.isEmpty { emptyState }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            if let error = model.error { errorBanner(error) }
        }
        .background(StickerPaper())
        .overlay {
            RoundedRectangle(cornerRadius: 13).strokeBorder(StickerCase.ink, lineWidth: 1.8)
                .padding(3).allowsHitTesting(false).accessibilityHidden(true)
        }
        .foregroundStyle(StickerCase.ink)
        .tint(StickerCase.ink)
        .frame(minWidth: 560, minHeight: 300)
        .preferredColorScheme(.light)
        .ignoresSafeArea(.container, edges: .top)
    }

    private var rule: some View {
        Rectangle().fill(StickerCase.ink).frame(height: 1.5).accessibilityHidden(true)
    }

    private var header: some View {
        ZStack {
            StickerWordmark()
            HStack {
                Spacer()
                MixerHeaderControls(appearance: $appearance, showSetup: showSetup)
            }
            .padding(.trailing, 16)
        }
        .frame(height: 68)
        .overlay(alignment: .bottom) { rule }
    }

    private var outputStrip: some View {
        HStack(spacing: 9) {
            Image(systemName: "headphones").font(.system(size: 20, weight: .semibold))
            Text(model.outputName.isEmpty ? "System output" : model.outputName)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1).truncationMode(.middle).help(model.outputName)
            Spacer(minLength: 12)
            Toggle("Boost", isOn: $model.boostEnabled)
                .font(.system(size: 12, weight: .bold))
                .toggleStyle(StickerBoostToggleStyle()).fixedSize()
                .help(MixerControlHelp.boost(model.boostEnabled))
                .accessibilityValue(model.boostEnabled ? "On" : "Off")
        }
        .padding(.horizontal, 20)
        .frame(height: 43)
    }

    private func appRow(_ row: AppGroup, accent: Color = StickerCase.teal) -> some View {
        let setting = model.setting(for: row)
        return HStack(spacing: 12) {
            Image(nsImage: row.identity.icon).resizable().frame(width: 38, height: 38)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.identity.name).font(.system(size: 14, weight: .bold))
                    .lineLimit(1).help(row.identity.name)
                Text(setting.isMuted ? "Muted" : row.isPlaying ? "Playing" : "Paused")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(StickerCase.secondary)
                AppOutputMenu(model: model, row: row, appearance: .stickerCase)
            }
            .frame(width: 142, alignment: .leading)
            Button { model.toggleMute(row) } label: {
                Image(systemName: setting.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(StickerCase.ink)
                    .symbolRenderingMode(.monochrome)
            }
            .buttonStyle(StickerButtonStyle(selected: setting.isMuted))
            .help(MixerControlHelp.mute(setting.isMuted))
            .accessibilityLabel(setting.isMuted ? "Unmute \(row.identity.name)" : "Mute \(row.identity.name)")
            .accessibilityValue(setting.isMuted ? "Muted" : "Not muted")

            StickerVolumeSlider(
                value: Binding(get: { min(setting.volume, model.maximumVolume) }, set: { model.setVolume($0, for: row) }),
                maximum: model.maximumVolume, isMuted: setting.isMuted, label: "\(row.identity.name) volume", accent: accent)
                .help(MixerControlHelp.volume(setting.volume, maximum: model.maximumVolume, muted: setting.isMuted))
            Text("\(Int((setting.volume * 100).rounded()))%")
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }

    private func browserGroup(_ row: AppGroup, chrome: ChromeTabModel) -> some View {
        VStack(spacing: 0) {
            appRow(row, accent: StickerCase.pink)
                .background(StickerPaper(tint: StickerCase.rose))
            rule
            ChromeTabsView(model: chrome, appearance: .stickerCase)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(StickerPaper(tint: StickerCase.mint))
        }
        .clipShape(StickerOutline(cut: 9))
        .overlay(StickerOutline(cut: 9).stroke(StickerCase.ink, lineWidth: 1.5))
        .padding(5)
        .background(StickerOutline(cut: 13).fill(.white))
        .overlay(StickerOutline(cut: 13).stroke(StickerCase.ink, lineWidth: 1.8))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "speaker.wave.2").font(.system(size: 26, weight: .bold))
            Text("Ready when you press play").font(.system(size: 14, weight: .bold))
            Text("Apps appear here when they play audio.")
                .font(.system(size: 12)).foregroundStyle(StickerCase.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(error).font(.system(size: 11, weight: .medium)).textSelection(.enabled)
            Spacer(minLength: 0)
            Button { model.error = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(StickerButtonStyle()).accessibilityLabel("Dismiss error")
        }
        .padding(14)
        .background(StickerCase.rose)
        .overlay(alignment: .top) { rule }
    }
}
