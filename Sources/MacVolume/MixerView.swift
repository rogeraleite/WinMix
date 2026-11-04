import SwiftUI

struct MixerView: View {
    @ObservedObject var model: MixerModel

    var body: some View {
        VStack(spacing: 0) {
            if model.rows.isEmpty {
                ContentUnavailableView(
                    "No apps are playing audio",
                    systemImage: "speaker.wave.2",
                    description: Text("Play something and it will show up here.")
                )
            } else {
                List(model.rows) { row in
                    AppRowView(
                        row: row,
                        setting: model.setting(for: row),
                        maximumVolume: model.maximumVolume,
                        setVolume: { model.setVolume($0, for: row) },
                        toggleMute: { model.toggleMute(row) }
                    )
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
            }

            if let error = model.error {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text(error).textSelection(.enabled)
                    Spacer()
                    Button("Dismiss") { model.error = nil }
                }
                .font(.callout)
                .padding(10)
                .background(.bar)
            }
        }
        .frame(minWidth: 400, minHeight: 200)
        .toolbar {
            Toggle(isOn: $model.boostEnabled) {
                Label("Boost", systemImage: "speaker.plus")
            }
            .help(model.boostEnabled ? "Sliders go up to 200%" : "Let sliders go up to 200%")
        }
    }
}

struct AppRowView: View {
    let row: AppGroup
    let setting: VolumeSetting
    let maximumVolume: Double
    let setVolume: (Double) -> Void
    let toggleMute: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: row.identity.icon)
                .resizable()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.identity.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(row.isPlaying ? "Playing" : "Paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 130, alignment: .leading)

            Button(action: toggleMute) {
                Image(systemName: speakerSymbol)
                    .frame(width: 20)
                    .foregroundStyle(setting.isMuted ? .red : .primary)
            }
            .buttonStyle(.borderless)
            .help(setting.isMuted ? "Unmute" : "Mute")
            .accessibilityLabel(setting.isMuted ? "Unmute \(row.identity.name)" : "Mute \(row.identity.name)")

            Slider(value: Binding(get: { min(setting.volume, maximumVolume) }, set: setVolume), in: 0...maximumVolume) {
                Text("\(row.identity.name) volume")
            }
            .labelsHidden()

            Text("\(Int((setting.volume * 100).rounded()))%")
                .monospacedDigit()
                .foregroundStyle(setting.isMuted ? AnyShapeStyle(.secondary) : setting.volume > 1 ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, 4)
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
